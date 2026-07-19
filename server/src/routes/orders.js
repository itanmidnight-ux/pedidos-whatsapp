'use strict';
const express = require('express');
const router  = express.Router();
const { staffAuth, adminAuth, clientAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');
const { notifyOrderStatus } = require('../utils/orderNotify');

const ACTIVE_STATUSES = "'pending','claimed','en_camino'";
const TZ = 'America/Bogota';

// helpers
// Antes: 1 query extra POR pedido (N+1) -- /history con 200 filas hacia 201
// queries por request. Ahora: 1 sola query trayendo los items de todos los
// pedidos de la pagina, agrupados en memoria.
async function ordersWithMeta(rows, db) {
  if (!rows.length) return [];
  const ids = rows.map(o => o.id);
  const { rows: items } = await db.query('SELECT * FROM order_items WHERE order_id = ANY($1)', [ids]);
  const byOrder = new Map();
  for (const it of items) {
    if (!byOrder.has(it.order_id)) byOrder.set(it.order_id, []);
    byOrder.get(it.order_id).push(it);
  }
  return rows.map(o => ({ ...o, items: byOrder.get(o.id) || [] }));
}

async function findOrder(db, id) {
  const { rows } = await db.query(`
    SELECT o.*, c.phone, c.name AS customer_name,
           u.username AS claimed_by_name, u.display_name AS claimed_by_display
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN users     u ON o.claimed_by  = u.id
    WHERE o.id = $1
  `, [id]);
  return rows[0] || null;
}

// GET /api/orders — active orders (pending + claimed + en_camino)
router.get('/', staffAuth, async (req, res, next) => {
  try {
    const db   = getDB();
    const { rows } = await db.query(`
      SELECT o.*, c.phone, c.name AS customer_name,
             u.username AS claimed_by_name, u.display_name AS claimed_by_display
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      LEFT JOIN users     u ON o.claimed_by  = u.id
      WHERE o.status IN (${ACTIVE_STATUSES})
      ORDER BY o.requested_at ASC
    `);
    res.json(await ordersWithMeta(rows, db));
  } catch (e) { next(e); }
});

// GET /api/orders/history — delivered + cancelled last N days
router.get('/history', staffAuth, async (req, res, next) => {
  try {
    const db   = getDB();
    const days = Math.min(Math.max(parseInt(req.query.days, 10) || 7, 1), 365);
    const cutoff = new Date(Date.now() - days * 86400000).toISOString();
    const { rows } = await db.query(`
      SELECT o.*, c.phone, c.name AS customer_name,
             u.username AS claimed_by_name, u.display_name AS claimed_by_display
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.id
      LEFT JOIN users     u ON o.claimed_by  = u.id
      WHERE o.status IN ('entregado','delivered','cancelled')
        AND o.requested_at::timestamptz >= $1::timestamptz
      ORDER BY o.requested_at DESC
      LIMIT 200
    `, [cutoff]);
    res.json(await ordersWithMeta(rows, db));
  } catch (e) { next(e); }
});

// GET /api/orders/stats — inventory totals + daily deliveries (admin only)
router.get('/stats', staffAuth, async (req, res, next) => {
  try {
    const db = getDB();

    // Product totals from active orders
    const { rows: productRowsRaw } = await db.query(`
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
      ) t
      GROUP BY name
      ORDER BY total DESC
    `);
    const productRows = productRowsRaw.map(r => ({ name: r.name, total: Number(r.total) }));

    // Delivered per day — last 7 days (dia calendario de Colombia, no UTC: un
    // pedido entregado a las 11pm en Colombia no debe contarse como del dia
    // siguiente)
    const { rows: dailyRowsRaw } = await db.query(`
      SELECT (delivered_at::timestamptz AT TIME ZONE '${TZ}')::date AS day, COUNT(*) AS count
      FROM orders
      WHERE status IN ('entregado','delivered')
        AND (delivered_at::timestamptz AT TIME ZONE '${TZ}')::date >= ((now() AT TIME ZONE '${TZ}')::date - INTERVAL '6 days')
      GROUP BY day
      ORDER BY day ASC
    `);
    const dailyRows = dailyRowsRaw.map(r => ({ day: r.day.toISOString().slice(0, 10), count: Number(r.count) }));

    // Summary counts
    const { rows: summaryRows } = await db.query(`
      SELECT
        COUNT(*) FILTER (WHERE status='pending') AS pending,
        COUNT(*) FILTER (WHERE status='claimed') AS claimed,
        COUNT(*) FILTER (WHERE status='en_camino') AS en_camino,
        COUNT(*) FILTER (WHERE status IN ('entregado','delivered')
          AND (delivered_at::timestamptz AT TIME ZONE '${TZ}')::date = (now() AT TIME ZONE '${TZ}')::date) AS delivered_today
      FROM orders
    `);
    const s = summaryRows[0];
    const summary = {
      pending: Number(s.pending), claimed: Number(s.claimed),
      en_camino: Number(s.en_camino), delivered_today: Number(s.delivered_today),
    };

    res.json({ product_totals: productRows, daily_deliveries: dailyRows, summary });
  } catch (e) { next(e); }
});

// GET /api/orders/mine — pedidos del cliente autenticado en la app (por su
// telefono registrado) -- debe ir antes de /:id para no ser capturada como id
router.get('/mine', clientAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const { rows: userRows } = await db.query('SELECT phone FROM users WHERE id=$1', [req.user.id]);
    if (!userRows[0]?.phone) return res.json([]);
    const { rows } = await db.query(`
      SELECT o.*, c.phone, c.name AS customer_name
      FROM orders o
      JOIN customers c ON o.customer_id = c.id
      WHERE c.phone = $1
      ORDER BY o.requested_at DESC
      LIMIT 30
    `, [userRows[0].phone]);
    res.json(await ordersWithMeta(rows, db));
  } catch (e) { next(e); }
});

// GET /api/orders/:id
router.get('/:id', staffAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const o  = await findOrder(db, parseInt(req.params.id, 10));
    if (!o) return res.status(404).json({ error: 'Pedido no encontrado' });
    const { rows: items } = await db.query('SELECT * FROM order_items WHERE order_id=$1', [o.id]);
    res.json({ ...o, items });
  } catch (e) { next(e); }
});

// PUT /api/orders/:id/claim — soft-lock: any worker can claim, admin can reassign
router.put('/:id/claim', staffAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const id = parseInt(req.params.id, 10);
    const { rows } = await db.query('SELECT * FROM orders WHERE id=$1', [id]);
    const o = rows[0];
    if (!o) return res.status(404).json({ error: 'Pedido no encontrado' });
    if (!['pending', 'claimed'].includes(o.status))
      return res.status(409).json({ error: `No se puede reclamar en estado: ${o.status}` });

    // If already claimed by someone else and not admin → conflict info
    if (o.claimed_by && o.claimed_by !== req.user.id && req.user.role !== 'admin') {
      const { rows: claimerRows } = await db.query('SELECT username, display_name FROM users WHERE id=$1', [o.claimed_by]);
      const claimer = claimerRows[0];
      return res.status(409).json({
        error: 'Pedido ya reclamado',
        claimed_by: claimer?.display_name || claimer?.username,
      });
    }

    await db.query(`UPDATE orders SET claimed_by=$1, claimed_at=now_iso(), status='claimed' WHERE id=$2`, [req.user.id, id]);
    res.json(await findOrder(db, id));
  } catch (e) { next(e); }
});

// PUT /api/orders/:id/unclaim — worker unclaims own; admin unclaims any
router.put('/:id/unclaim', staffAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const id = parseInt(req.params.id, 10);
    const { rows } = await db.query('SELECT * FROM orders WHERE id=$1', [id]);
    const o = rows[0];
    if (!o) return res.status(404).json({ error: 'Pedido no encontrado' });

    if (req.user.role !== 'admin' && o.claimed_by !== req.user.id)
      return res.status(403).json({ error: 'Solo puedes liberar tus propios pedidos' });

    await db.query("UPDATE orders SET claimed_by=NULL, claimed_at=NULL, status='pending' WHERE id=$1", [id]);
    res.json(await findOrder(db, id));
  } catch (e) { next(e); }
});

// PUT /api/orders/:id/en_camino — claimer or admin
router.put('/:id/en_camino', staffAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const id = parseInt(req.params.id, 10);
    const { rows } = await db.query('SELECT * FROM orders WHERE id=$1', [id]);
    const o = rows[0];
    if (!o) return res.status(404).json({ error: 'Pedido no encontrado' });

    if (req.user.role !== 'admin' && o.claimed_by !== req.user.id)
      return res.status(403).json({ error: 'Solo el empleado asignado puede marcar en camino' });
    if (!['claimed', 'pending'].includes(o.status))
      return res.status(409).json({ error: `Estado inválido para marcar en camino: ${o.status}` });

    const claimed = o.claimed_by || req.user.id;
    await db.query("UPDATE orders SET status='en_camino', claimed_by=$1 WHERE id=$2", [claimed, id]);
    const full = await findOrder(db, id);
    notifyOrderStatus(full);
    res.json(full);
  } catch (e) { next(e); }
});

// PUT /api/orders/:id/deliver — mark entregado (worker/admin only)
router.put('/:id/deliver', staffAuth, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
    const db = getDB();
    // UTC, igual que requested_at -- antes se guardaba en hora local sin
    // marca de zona, y julianday() las restaba como si ambas fueran UTC,
    // dando tiempos de entrega negativos.
    await db.query(`UPDATE orders SET status='entregado', delivered_at=now_iso() WHERE id=$1`, [id]);
    const full = await findOrder(db, id);
    notifyOrderStatus(full);
    res.json(full);
  } catch (e) { next(e); }
});

// PUT /api/orders/:id/cancel — admin only
router.put('/:id/cancel', adminAuth, async (req, res, next) => {
  try {
    const { reason } = req.body;
    if (!reason || typeof reason !== 'string' || !reason.trim())
      return res.status(400).json({ error: 'Motivo de cancelación requerido' });
    const db = getDB();
    const id = parseInt(req.params.id, 10);
    const { rows } = await db.query('SELECT id FROM orders WHERE id=$1', [id]);
    if (!rows[0]) return res.status(404).json({ error: 'Pedido no encontrado' });
    await db.query("UPDATE orders SET status='cancelled', cancel_reason=$1 WHERE id=$2", [reason.trim(), id]);
    const full = await findOrder(db, id);
    notifyOrderStatus(full);
    res.json(full);
  } catch (e) { next(e); }
});

// PUT /api/orders/:id/comment
router.put('/:id/comment', staffAuth, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
    const { comment } = req.body;
    if (comment !== undefined && (typeof comment !== 'string' || comment.length > 500))
      return res.status(400).json({ error: 'comment máximo 500 caracteres' });
    await getDB().query('UPDATE orders SET comment=$1 WHERE id=$2', [comment || null, id]);
    res.json({ ok: true });
  } catch (e) { next(e); }
});

// Legacy route — keep backward compat
router.get('/pending', staffAuth, async (req, res, next) => {
  try {
    const today = new Date().toISOString().split('T')[0];
    const db    = getDB();
    const { rows } = await db.query(`
      SELECT o.*, c.phone, c.name AS customer_name
      FROM orders o LEFT JOIN customers c ON o.customer_id = c.id
      WHERE o.status = 'pending' AND (o.requested_at::timestamptz)::date < $1::date
      ORDER BY o.requested_at ASC
    `, [today]);
    res.json(rows);
  } catch (e) { next(e); }
});

module.exports = router;
