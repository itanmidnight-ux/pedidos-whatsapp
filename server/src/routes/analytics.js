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
    WHERE o.status IN ('entregado','delivered') AND date(o.delivered_at) = date('now')
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

  res.json({
    sales_today: salesToday,
    avg_ticket: Math.round(avgTicket),
    cancelled_pct: cancelledPct,
    delivered_total: counts.delivered,
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
router.get('/employees', adminAuth, (req, res) => {
  const db = getDB();
  const employees = db.prepare(`
    SELECT u.id, u.username, u.display_name,
      COUNT(*) AS delivered_count,
      ROUND(AVG((julianday(o.delivered_at) - julianday(o.requested_at)) * 24 * 60)) AS avg_minutes
    FROM orders o
    JOIN users u ON u.id = o.claimed_by
    WHERE o.status IN ('entregado','delivered')
    GROUP BY u.id
    ORDER BY delivered_count DESC
  `).all();
  res.json({ employees });
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
