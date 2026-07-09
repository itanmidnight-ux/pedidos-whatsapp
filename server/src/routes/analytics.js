'use strict';
const express = require('express');
const router  = express.Router();
const { adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

// GET /api/analytics/summary
router.get('/summary', adminAuth, (req, res) => {
  const db = getDB();
  const salesToday = db.prepare(`
    SELECT COALESCE(SUM(oi.product_price * oi.quantity), 0) AS total
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.id
    WHERE o.status IN ('entregado','delivered') AND date(o.delivered_at,'localtime') = date('now','localtime')
  `).get().total;

  const avgTicket = db.prepare(`
    SELECT COALESCE(AVG(order_total), 0) AS avg FROM (
      SELECT o.id, SUM(oi.product_price * oi.quantity) AS order_total
      FROM orders o JOIN order_items oi ON oi.order_id = o.id
      WHERE o.status IN ('entregado','delivered')
      GROUP BY o.id
    )
  `).get().avg;

  const counts = db.prepare(`
    SELECT
      COUNT(*) FILTER (WHERE status IN ('entregado','delivered')) AS delivered,
      COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled,
      COUNT(*) AS total
    FROM orders
  `).get();

  const cancelledPct = counts.total > 0 ? Math.round((counts.cancelled / counts.total) * 100) : 0;

  // Distribución por estado -- para el donut de la app/panel
  const statusRows = db.prepare(`
    SELECT status, COUNT(*) AS count FROM orders
    WHERE status IN ('pending','claimed','en_camino','entregado','delivered','cancelled')
    GROUP BY status
  `).all();
  const statusBreakdown = statusRows.map(r => ({ status: r.status, count: r.count }));

  // Ingresos por día -- últimos 7 días, para el gráfico de barras
  const dayRows = db.prepare(`
    SELECT date(o.delivered_at,'localtime') AS d, SUM(oi.product_price * oi.quantity) AS total
    FROM orders o JOIN order_items oi ON oi.order_id = o.id
    WHERE o.status IN ('entregado','delivered') AND date(o.delivered_at,'localtime') >= date('now','-6 days','localtime')
    GROUP BY d ORDER BY d
  `).all();
  const byDate = Object.fromEntries(dayRows.map(r => [r.d, r.total]));
  const dailySales = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    const iso = d.toISOString().slice(0, 10);
    dailySales.push({ date: iso, total: byDate[iso] || 0 });
  }

  res.json({
    sales_today: salesToday,
    avg_ticket: Math.round(avgTicket),
    cancelled_pct: cancelledPct,
    delivered_total: counts.delivered,
    status_breakdown: statusBreakdown,
    daily_sales: dailySales,
  });
});

// GET /api/analytics/products
router.get('/products', adminAuth, (req, res) => {
  const db = getDB();
  const topProducts = db.prepare(`
    SELECT oi.product_name AS name, SUM(oi.quantity) AS total_qty
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.status IN ('entregado','delivered')
    GROUP BY oi.product_name
    ORDER BY total_qty DESC
    LIMIT 10
  `).all();

  const lowStock = db.prepare(`
    SELECT id, name, stock, low_stock_threshold
    FROM products
    WHERE stock IS NOT NULL AND low_stock_threshold IS NOT NULL AND stock <= low_stock_threshold
    ORDER BY stock ASC
  `).all();

  res.json({ top_products: topProducts, low_stock: lowStock });
});

// GET /api/analytics/employees
// Antes solo listaba a quien tuviera entregas -- un trabajador que no
// entrego nada (ej. no inicio turno) directamente no aparecia. Ahora
// lista TODO el staff activo, con su estado de sesion (activo ahora,
// inicio sesion hoy) para poder detectar quien falta.
router.get('/employees', adminAuth, (req, res) => {
  const db = getDB();
  const employees = db.prepare(`
    SELECT u.id, u.username, u.display_name, u.role,
      COALESCE(d.delivered_count, 0) AS delivered_count,
      d.avg_minutes,
      le.logged_in_at  AS last_login_at,
      le.logged_out_at AS last_logout_at,
      CASE WHEN le.logged_in_at IS NOT NULL
        AND date(le.logged_in_at, 'localtime') = date('now','localtime')
        THEN 1 ELSE 0 END AS logged_in_today,
      CASE WHEN le.logged_in_at IS NOT NULL AND le.logged_out_at IS NULL
        THEN 1 ELSE 0 END AS is_active_now
    FROM users u
    LEFT JOIN (
      SELECT claimed_by AS user_id, COUNT(*) AS delivered_count,
        ROUND(AVG((julianday(delivered_at) - julianday(requested_at)) * 24 * 60)) AS avg_minutes
      FROM orders WHERE status IN ('entregado','delivered') GROUP BY claimed_by
    ) d ON d.user_id = u.id
    LEFT JOIN (
      SELECT le1.user_id, le1.logged_in_at, le1.logged_out_at
      FROM login_events le1
      WHERE le1.id = (SELECT MAX(le2.id) FROM login_events le2 WHERE le2.user_id = le1.user_id)
    ) le ON le.user_id = u.id
    WHERE u.role IN ('admin','worker') AND u.active = 1
    ORDER BY is_active_now DESC, logged_in_today ASC, u.display_name ASC
  `).all();
  res.json({ employees });
});

// GET /api/analytics/employees/:id — detalle: historial de sesiones
router.get('/employees/:id', adminAuth, (req, res) => {
  const db = getDB();
  const id = parseInt(req.params.id, 10);
  const user = db.prepare(
    `SELECT id, username, display_name, role, active FROM users WHERE id=? AND role IN ('admin','worker')`
  ).get(id);
  if (!user) return res.status(404).json({ error: 'Empleado no encontrado' });

  const sessions = db.prepare(
    `SELECT logged_in_at, logged_out_at FROM login_events WHERE user_id=? ORDER BY id DESC LIMIT 20`
  ).all(id);

  const stats = db.prepare(`
    SELECT COUNT(*) AS delivered_count,
      ROUND(AVG((julianday(delivered_at) - julianday(requested_at)) * 24 * 60)) AS avg_minutes
    FROM orders WHERE status IN ('entregado','delivered') AND claimed_by = ?
  `).get(id);

  res.json({ user, sessions, stats });
});

// GET /api/analytics/customers
router.get('/customers', adminAuth, (req, res) => {
  const db = getDB();
  const days = Math.min(Math.max(parseInt(req.query.days, 10) || 30, 1), 365);

  const newCustomers = db.prepare(`
    SELECT COUNT(*) AS c FROM customers
    WHERE datetime(created_at) >= datetime('now', ?)
  `).get(`-${days} days`).c;

  const returning = db.prepare(`
    SELECT COUNT(*) AS c FROM (
      SELECT customer_id FROM orders
      WHERE customer_id IS NOT NULL
      GROUP BY customer_id HAVING COUNT(*) > 1
    )
  `).get().c;

  const topCustomers = db.prepare(`
    SELECT c.name, c.phone, COUNT(*) AS order_count
    FROM orders o JOIN customers c ON c.id = o.customer_id
    WHERE o.status IN ('entregado','delivered')
    GROUP BY o.customer_id
    ORDER BY order_count DESC
    LIMIT 10
  `).all();

  res.json({ new_customers: newCustomers, returning_customers: returning, top_customers: topCustomers });
});

module.exports = router;
