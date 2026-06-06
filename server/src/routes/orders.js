'use strict';
const express = require('express');
const router  = express.Router();
const { jwtAuth, adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

const ACTIVE_STATUSES = "'pending','claimed','en_camino'";

// helpers
function ordersWithMeta(rows, db) {
  return rows.map(o => {
    const items = db.prepare('SELECT * FROM order_items WHERE order_id=?').all(o.id);
    return { ...o, items };
  });
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
router.get('/', jwtAuth, (req, res) => {
  const db   = getDB();
  const rows = db.prepare(`
    SELECT o.*, c.phone, c.name AS customer_name,
           u.username AS claimed_by_name, u.display_name AS claimed_by_display
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN users     u ON o.claimed_by  = u.id
    WHERE o.status IN (${ACTIVE_STATUSES})
    ORDER BY o.requested_at DESC
  `).all();
  res.json(ordersWithMeta(rows, db));
});

// GET /api/orders/history — delivered + cancelled last N days
router.get('/history', jwtAuth, (req, res) => {
  const db   = getDB();
  const days = Math.min(Math.max(parseInt(req.query.days, 10) || 7, 1), 365);
  const cutoff = new Date(Date.now() - days * 86400000).toISOString().slice(0, 19).replace('T', ' ');
  const rows = db.prepare(`
    SELECT o.*, c.phone, c.name AS customer_name,
           u.username AS claimed_by_name
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

// GET /api/orders/:id
router.get('/:id', jwtAuth, (req, res) => {
  const db = getDB();
  const o  = findOrder(db, parseInt(req.params.id));
  if (!o) return res.status(404).json({ error: 'Pedido no encontrado' });
  const items = db.prepare('SELECT * FROM order_items WHERE order_id=?').all(o.id);
  res.json({ ...o, items });
});

// PUT /api/orders/:id/claim — soft-lock: any worker can claim, admin can reassign
router.put('/:id/claim', jwtAuth, (req, res) => {
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
router.put('/:id/unclaim', jwtAuth, (req, res) => {
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
router.put('/:id/en_camino', jwtAuth, (req, res) => {
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
router.put('/:id/deliver', jwtAuth, (req, res) => {
  if (!['admin', 'worker'].includes(req.user.role))
    return res.status(403).json({ error: 'Solo empleados pueden marcar como entregado' });
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const db = getDB();
  db.prepare(`UPDATE orders SET status='entregado', delivered_at=datetime('now','localtime') WHERE id=?`).run(id);
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
router.put('/:id/comment', jwtAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const { comment } = req.body;
  if (comment !== undefined && (typeof comment !== 'string' || comment.length > 500))
    return res.status(400).json({ error: 'comment máximo 500 caracteres' });
  getDB().prepare('UPDATE orders SET comment=? WHERE id=?').run(comment || null, id);
  res.json({ ok: true });
});

// Legacy route — keep backward compat
router.get('/pending', jwtAuth, (req, res) => {
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
