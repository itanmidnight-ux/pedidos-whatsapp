'use strict';
const express = require('express');
const router  = express.Router();
const { adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

// Colombia es UTC-5 fijo todo el año (sin horario de verano) -- se usa el
// nombre de zona IANA explicito en vez de asumir la zona del servidor.
const TZ = 'America/Bogota';

// GET /api/analytics/summary
router.get('/summary', adminAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const { rows: salesRows } = await db.query(`
      SELECT COALESCE(SUM(oi.product_price * oi.quantity), 0) AS total
      FROM orders o
      JOIN order_items oi ON oi.order_id = o.id
      WHERE o.status IN ('entregado','delivered')
        AND (o.delivered_at::timestamptz AT TIME ZONE '${TZ}')::date = (now() AT TIME ZONE '${TZ}')::date
    `);
    const salesToday = Number(salesRows[0].total);

    const { rows: avgRows } = await db.query(`
      SELECT COALESCE(AVG(order_total), 0) AS avg FROM (
        SELECT o.id, SUM(oi.product_price * oi.quantity) AS order_total
        FROM orders o JOIN order_items oi ON oi.order_id = o.id
        WHERE o.status IN ('entregado','delivered')
        GROUP BY o.id
      ) t
    `);
    const avgTicket = Number(avgRows[0].avg);

    const { rows: countRows } = await db.query(`
      SELECT
        COUNT(*) FILTER (WHERE status IN ('entregado','delivered')) AS delivered,
        COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled,
        COUNT(*) AS total
      FROM orders
    `);
    const counts = {
      delivered: Number(countRows[0].delivered),
      cancelled: Number(countRows[0].cancelled),
      total: Number(countRows[0].total),
    };

    const cancelledPct = counts.total > 0 ? Math.round((counts.cancelled / counts.total) * 100) : 0;

    // Distribución por estado -- para el donut de la app/panel
    const { rows: statusRows } = await db.query(`
      SELECT status, COUNT(*) AS count FROM orders
      WHERE status IN ('pending','claimed','en_camino','entregado','delivered','cancelled')
      GROUP BY status
    `);
    const statusBreakdown = statusRows.map(r => ({ status: r.status, count: Number(r.count) }));

    // Ingresos por día -- últimos 7 días, para el gráfico de barras
    const { rows: dayRows } = await db.query(`
      SELECT (o.delivered_at::timestamptz AT TIME ZONE '${TZ}')::date AS d,
        SUM(oi.product_price * oi.quantity) AS total
      FROM orders o JOIN order_items oi ON oi.order_id = o.id
      WHERE o.status IN ('entregado','delivered')
        AND (o.delivered_at::timestamptz AT TIME ZONE '${TZ}')::date >= ((now() AT TIME ZONE '${TZ}')::date - INTERVAL '6 days')
      GROUP BY d ORDER BY d
    `);
    const byDate = Object.fromEntries(dayRows.map(r => [r.d.toISOString().slice(0, 10), Number(r.total)]));
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
  } catch (e) { next(e); }
});

// GET /api/analytics/products
router.get('/products', adminAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const { rows: topProductsRaw } = await db.query(`
      SELECT oi.product_name AS name, SUM(oi.quantity) AS total_qty
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      WHERE o.status IN ('entregado','delivered')
      GROUP BY oi.product_name
      ORDER BY total_qty DESC
      LIMIT 10
    `);
    const topProducts = topProductsRaw.map(r => ({ name: r.name, total_qty: Number(r.total_qty) }));

    const { rows: lowStock } = await db.query(`
      SELECT id, name, stock, low_stock_threshold
      FROM products
      WHERE stock IS NOT NULL AND low_stock_threshold IS NOT NULL AND stock <= low_stock_threshold
      ORDER BY stock ASC
    `);

    res.json({ top_products: topProducts, low_stock: lowStock });
  } catch (e) { next(e); }
});

// GET /api/analytics/employees
// Antes solo listaba a quien tuviera entregas -- un trabajador que no
// entrego nada (ej. no inicio turno) directamente no aparecia. Ahora
// lista TODO el staff activo, con su estado de sesion (activo ahora,
// inicio sesion hoy) para poder detectar quien falta.
router.get('/employees', adminAuth, async (req, res, next) => {
  try {
    const { rows: employees } = await getDB().query(`
      SELECT u.id, u.username, u.display_name, u.role,
        COALESCE(d.delivered_count, 0) AS delivered_count,
        d.avg_minutes,
        le.logged_in_at  AS last_login_at,
        le.logged_out_at AS last_logout_at,
        CASE WHEN le.logged_in_at IS NOT NULL
          AND (le.logged_in_at::timestamptz AT TIME ZONE '${TZ}')::date = (now() AT TIME ZONE '${TZ}')::date
          THEN 1 ELSE 0 END AS logged_in_today,
        CASE WHEN le.logged_in_at IS NOT NULL AND le.logged_out_at IS NULL
          THEN 1 ELSE 0 END AS is_active_now
      FROM users u
      LEFT JOIN (
        SELECT claimed_by AS user_id, COUNT(*) AS delivered_count,
          ROUND(AVG(EXTRACT(EPOCH FROM (delivered_at::timestamptz - requested_at::timestamptz)) / 60)) AS avg_minutes
        FROM orders WHERE status IN ('entregado','delivered') GROUP BY claimed_by
      ) d ON d.user_id = u.id
      LEFT JOIN (
        SELECT le1.user_id, le1.logged_in_at, le1.logged_out_at
        FROM login_events le1
        WHERE le1.id = (SELECT MAX(le2.id) FROM login_events le2 WHERE le2.user_id = le1.user_id)
      ) le ON le.user_id = u.id
      WHERE u.role IN ('admin','worker') AND u.active = 1
      ORDER BY is_active_now DESC, logged_in_today ASC, u.display_name ASC
    `);
    res.json({
      employees: employees.map(e => ({
        ...e,
        delivered_count: Number(e.delivered_count),
        avg_minutes: e.avg_minutes !== null ? Number(e.avg_minutes) : null,
      })),
    });
  } catch (e) { next(e); }
});

// GET /api/analytics/employees/:id — detalle: historial de sesiones
router.get('/employees/:id', adminAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const id = parseInt(req.params.id, 10);
    const { rows: userRows } = await db.query(
      `SELECT id, username, display_name, role, active FROM users WHERE id=$1 AND role IN ('admin','worker')`, [id]
    );
    const user = userRows[0];
    if (!user) return res.status(404).json({ error: 'Empleado no encontrado' });

    const { rows: sessions } = await db.query(
      `SELECT logged_in_at, logged_out_at FROM login_events WHERE user_id=$1 ORDER BY id DESC LIMIT 20`, [id]
    );

    const { rows: statsRows } = await db.query(`
      SELECT COUNT(*) AS delivered_count,
        ROUND(AVG(EXTRACT(EPOCH FROM (delivered_at::timestamptz - requested_at::timestamptz)) / 60)) AS avg_minutes
      FROM orders WHERE status IN ('entregado','delivered') AND claimed_by = $1
    `, [id]);
    const stats = {
      delivered_count: Number(statsRows[0].delivered_count),
      avg_minutes: statsRows[0].avg_minutes !== null ? Number(statsRows[0].avg_minutes) : null,
    };

    res.json({ user, sessions, stats });
  } catch (e) { next(e); }
});

// GET /api/analytics/customers
router.get('/customers', adminAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const days = Math.min(Math.max(parseInt(req.query.days, 10) || 30, 1), 365);

    const { rows: newRows } = await db.query(`
      SELECT COUNT(*) AS c FROM customers
      WHERE created_at::timestamptz >= now() - ($1 * INTERVAL '1 day')
    `, [days]);
    const newCustomers = Number(newRows[0].c);

    const { rows: returningRows } = await db.query(`
      SELECT COUNT(*) AS c FROM (
        SELECT customer_id FROM orders
        WHERE customer_id IS NOT NULL
        GROUP BY customer_id HAVING COUNT(*) > 1
      ) t
    `);
    const returning = Number(returningRows[0].c);

    const { rows: topCustomersRaw } = await db.query(`
      SELECT c.name, c.phone, COUNT(*) AS order_count
      FROM orders o JOIN customers c ON c.id = o.customer_id
      WHERE o.status IN ('entregado','delivered')
      GROUP BY o.customer_id, c.name, c.phone
      ORDER BY order_count DESC
      LIMIT 10
    `);
    const topCustomers = topCustomersRaw.map(r => ({ ...r, order_count: Number(r.order_count) }));

    res.json({ new_customers: newCustomers, returning_customers: returning, top_customers: topCustomers });
  } catch (e) { next(e); }
});

module.exports = router;
