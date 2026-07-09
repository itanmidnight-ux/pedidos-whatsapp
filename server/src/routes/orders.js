'use strict';
const express = require('express');
const router  = express.Router();
const { staffAuth, adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

const ACTIVE_STATUSES = "'pending','claimed','en_camino'";

// helpers
// Antes: 1 query extra POR pedido (N+1) -- /history con 200 filas hacia 201
// queries por request. Ahora: 1 sola query trayendo los items de todos los
// pedidos de la pagina, agrupados en memoria.
function ordersWithMeta(rows, db) {
  if (!rows.length) return [];
  const ids = rows.map(o => o.id);
  const placeholders = ids.map(() => '?').join(',');
  const items = db.prepare(`SELECT * FROM order_items WHERE order_id IN (${placeholders})`).all(...ids);
  const byOrder = new Map();
  for (const it of items) {
    if (!byOrder.has(it.order_id)) byOrder.set(it.order_id, []);
    byOrder.get(it.order_id).push(it);
  }
  return rows.map(o => ({ ...o, items: byOrder.get(o.id) || [] }));
}

function findOrder(db, id) {
  return db.prepare(`
    SELECT o.*, c.phone, c.name AS customer_name,
           u.username AS claimed_by_name, u.display_name AS claimed_by_display
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN users     u ON o.claimed_by  = u.id
    WHERE o.id = ?
  `).get(id);
}

// GET /api/orders — active orders (pending + claimed + en_camino)
router.get('/', staffAuth, (req, res) => {
  const db   = getDB();
  const rows = db.prepare(`
    SELECT o.*, c.phone, c.name AS customer_name,
           u.username AS claimed_by_name, u.display_name AS claimed_by_display
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN users     u ON o.claimed_by  = u.id
    WHERE o.status IN (${ACTIVE_STATUSES})
    ORDER BY o.requested_at ASC
  `).all();
  res.json(ordersWithMeta(rows, db));
});

// GET /api/orders/history — delivered + cancelled last N days
router.get('/history', staffAuth, (req, res) => {
  const db   = getDB();
  const days = Math.min(Math.max(parseInt(req.query.days, 10) || 7, 1), 365);
  const cutoff = new Date(Date.now() - days * 86400000).toISOString().slice(0, 19).replace('T', ' ');
  const rows = db.prepare(`
    SELECT o.*, c.phone, c.name AS customer_name,
           u.username AS claimed_by_name, u.display_name AS claimed_by_display
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN users     u ON o.claimed_by  = u.id
    WHERE o.status IN ('entregado','delivered','cancelled')
      AND datetime(o.requested_at) >= ?
    ORDER BY o.requested_at DESC
    LIMIT 200
  `).all(cutoff);
  res.json(ordersWithMeta(rows, db));
});

// GET /api/orders/stats — inventory totals + daily deliveries (admin only)
router.get('/stats', staffAuth, (req, res) => {
  const db = getDB();

  // Product totals from active orders
  const productRows = db.prepare(`
    SELECT name, SUM(qty) AS total FROM (
      SELECT oi.product_name AS name, oi.quantity AS qty
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      WHERE o.status IN (${ACTIVE_STATUSES})
      UNION ALL
      SELECT o.product_name AS name, 1 AS qty
      FROM orders o
      WHERE o.status IN (${ACTIVE_STATUSES})
        AND NOT EXISTS (SELECT 1 FROM order_items WHERE order_id = o.id)
        AND o.product_name IS NOT NULL
    )
    GROUP BY name
    ORDER BY total DESC
  `).all();

  // Delivered per day — last 7 days (dia calendario LOCAL, no UTC: un pedido
  // entregado a las 11pm en Colombia no debe contarse como del dia siguiente)
  const dailyRows = db.prepare(`
    SELECT date(delivered_at, 'localtime') AS day, COUNT(*) AS count
    FROM orders
    WHERE status IN ('entregado','delivered')
      AND date(delivered_at, 'localtime') >= date('now','-6 days','localtime')
    GROUP BY date(delivered_at, 'localtime')
    ORDER BY day ASC
  `).all();

  // Summary counts
  const summary = db.prepare(`
    SELECT
      COUNT(*) FILTER (WHERE status='pending') AS pending,
      COUNT(*) FILTER (WHERE status='claimed') AS claimed,
      COUNT(*) FILTER (WHERE status='en_camino') AS en_camino,
      COUNT(*) FILTER (WHERE status IN ('entregado','delivered') AND date(delivered_at,'localtime')=date('now','localtime')) AS delivered_today
    FROM orders
  `).get();

  res.json({ product_totals: productRows, daily_deliveries: dailyRows, summary });
});

// GET /api/orders/:id
router.get('/:id', staffAuth, (req, res) => {
  const db = getDB();
  const o  = findOrder(db, parseInt(req.params.id));
  if (!o) return res.status(404).json({ error: 'Pedido no encontrado' });
  const items = db.prepare('SELECT * FROM order_items WHERE order_id=?').all(o.id);
  res.json({ ...o, items });
});

// PUT /api/orders/:id/claim — soft-lock: any worker can claim, admin can reassign
router.put('/:id/claim', staffAuth, (req, res) => {
  const db = getDB();
  const id = parseInt(req.params.id);
  const o  = db.prepare('SELECT * FROM orders WHERE id=?').get(id);
  if (!o) return res.status(404).json({ error: 'Pedido no encontrado' });
  if (!['pending', 'claimed'].includes(o.status))
    return res.status(409).json({ error: `No se puede reclamar en estado: ${o.status}` });

  // If already claimed by someone else and not admin → conflict info
  if (o.claimed_by && o.claimed_by !== req.user.id && req.user.role !== 'admin') {
    const claimer = db.prepare('SELECT username, display_name FROM users WHERE id=?').get(o.claimed_by);
    return res.status(409).json({
      error: 'Pedido ya reclamado',
      claimed_by: claimer?.display_name || claimer?.username
    });
  }

  db.prepare(`UPDATE orders SET claimed_by=?, claimed_at=datetime('now','localtime'), status='claimed' WHERE id=?`)
    .run(req.user.id, id);
  res.json(findOrder(db, id));
});

// PUT /api/orders/:id/unclaim — worker unclaims own; admin unclaims any
router.put('/:id/unclaim', staffAuth, (req, res) => {
  const db = getDB();
  const id = parseInt(req.params.id);
  const o  = db.prepare('SELECT * FROM orders WHERE id=?').get(id);
  if (!o) return res.status(404).json({ error: 'Pedido no encontrado' });

  if (req.user.role !== 'admin' && o.claimed_by !== req.user.id)
    return res.status(403).json({ error: 'Solo puedes liberar tus propios pedidos' });

  db.prepare("UPDATE orders SET claimed_by=NULL, claimed_at=NULL, status='pending' WHERE id=?").run(id);
  res.json(findOrder(db, id));
});

// PUT /api/orders/:id/en_camino — claimer or admin
router.put('/:id/en_camino', staffAuth, (req, res) => {
  const db = getDB();
  const id = parseInt(req.params.id);
  const o  = db.prepare('SELECT * FROM orders WHERE id=?').get(id);
  if (!o) return res.status(404).json({ error: 'Pedido no encontrado' });

  if (req.user.role !== 'admin' && o.claimed_by !== req.user.id)
    return res.status(403).json({ error: 'Solo el empleado asignado puede marcar en camino' });
  if (!['claimed', 'pending'].includes(o.status))
    return res.status(409).json({ error: `Estado inválido para marcar en camino: ${o.status}` });

  const claimed = o.claimed_by || req.user.id;
  db.prepare("UPDATE orders SET status='en_camino', claimed_by=? WHERE id=?").run(claimed, id);
  res.json(findOrder(db, id));
});

// PUT /api/orders/:id/deliver — mark entregado (worker/admin only)
router.put('/:id/deliver', staffAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const db = getDB();
  // UTC, igual que requested_at (new Date().toISOString() en JS) -- antes
  // se guardaba en hora local sin marca de zona, y julianday() las restaba
  // como si ambas fueran UTC, dando tiempos de entrega negativos.
  db.prepare(`UPDATE orders SET status='entregado', delivered_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=?`).run(id);
  res.json(findOrder(db, id));
});

// PUT /api/orders/:id/cancel — admin only
router.put('/:id/cancel', adminAuth, (req, res) => {
  const { reason } = req.body;
  if (!reason || typeof reason !== 'string' || !reason.trim())
    return res.status(400).json({ error: 'Motivo de cancelación requerido' });
  const db = getDB();
  const id = parseInt(req.params.id);
  const o  = db.prepare('SELECT id FROM orders WHERE id=?').get(id);
  if (!o) return res.status(404).json({ error: 'Pedido no encontrado' });
  db.prepare("UPDATE orders SET status='cancelled', cancel_reason=? WHERE id=?").run(reason.trim(), id);
  res.json(findOrder(db, id));
});

// PUT /api/orders/:id/comment
router.put('/:id/comment', staffAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const { comment } = req.body;
  if (comment !== undefined && (typeof comment !== 'string' || comment.length > 500))
    return res.status(400).json({ error: 'comment máximo 500 caracteres' });
  getDB().prepare('UPDATE orders SET comment=? WHERE id=?').run(comment || null, id);
  res.json({ ok: true });
});

// DELETE /api/orders/bulk — borra uno, varios o todos los pedidos (admin)
// body: { ids: [1,2,3] } o { all: true }
router.delete('/bulk', adminAuth, (req, res) => {
  const { ids, all } = req.body;
  const db = getDB();
  if (all === true) {
    const { changes } = db.prepare('DELETE FROM orders').run();
    return res.json({ success: true, deleted: changes });
  }
  if (!Array.isArray(ids) || !ids.length || !ids.every(n => Number.isInteger(n)))
    return res.status(400).json({ error: 'ids requerido (array de enteros) o all=true' });
  const placeholders = ids.map(() => '?').join(',');
  const { changes } = db.prepare(`DELETE FROM orders WHERE id IN (${placeholders})`).run(...ids);
  res.json({ success: true, deleted: changes });
});

// Legacy route — keep backward compat
router.get('/pending', staffAuth, (req, res) => {
  const today = new Date().toISOString().split('T')[0];
  const db    = getDB();
  const rows  = db.prepare(`
    SELECT o.*, c.phone, c.name AS customer_name
    FROM orders o LEFT JOIN customers c ON o.customer_id = c.id
    WHERE o.status = 'pending' AND date(o.requested_at) < ?
    ORDER BY o.requested_at ASC
  `).all(today);
  res.json(rows);
});

module.exports = router;
