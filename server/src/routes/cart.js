'use strict';
const express = require('express');
const router  = express.Router();
const { clientAuth, adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

// GET /api/cart — get my cart items
router.get('/', clientAuth, (req, res) => {
  const items = getDB().prepare(`
    SELECT ci.*, p.name as product_name, p.price, p.available
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    WHERE ci.client_username = ?
    ORDER BY ci.created_at ASC
  `).all(req.user.username);
  res.json({ items });
});

// POST /api/cart — add/update item
router.post('/', clientAuth, (req, res) => {
  const { product_id, quantity, delivery_date } = req.body;
  if (!product_id || !quantity || quantity < 1)
    return res.status(400).json({ error: 'product_id y quantity requeridos' });
  const db = getDB();
  if (!db.prepare('SELECT id FROM products WHERE id=? AND available=1').get(product_id))
    return res.status(404).json({ error: 'Producto no disponible' });
  const existing = db.prepare('SELECT id FROM cart_items WHERE client_username=? AND product_id=?')
    .get(req.user.username, product_id);
  if (existing) {
    db.prepare('UPDATE cart_items SET quantity=?, delivery_date=? WHERE id=?')
      .run(quantity, delivery_date || null, existing.id);
  } else {
    db.prepare('INSERT INTO cart_items (client_username, product_id, quantity, delivery_date) VALUES (?,?,?,?)')
      .run(req.user.username, product_id, quantity, delivery_date || null);
  }
  res.json({ ok: true });
});

// DELETE /api/cart/:product_id — remove item
router.delete('/:product_id', clientAuth, (req, res) => {
  getDB().prepare('DELETE FROM cart_items WHERE client_username=? AND product_id=?')
    .run(req.user.username, req.params.product_id);
  res.json({ ok: true });
});

// DELETE /api/cart — clear cart
router.delete('/', clientAuth, (req, res) => {
  getDB().prepare('DELETE FROM cart_items WHERE client_username=?').run(req.user.username);
  res.json({ ok: true });
});

// POST /api/cart/checkout — place order from cart
router.post('/checkout', clientAuth, (req, res) => {
  const { payment_method, nequi_reference, delivery_date } = req.body;
  if (!['nequi', 'contra_entrega'].includes(payment_method))
    return res.status(400).json({ error: 'payment_method debe ser nequi o contra_entrega' });
  if (payment_method === 'nequi' && !nequi_reference)
    return res.status(400).json({ error: 'nequi_reference requerido para pago Nequi' });

  const db = getDB();
  const items = db.prepare(`
    SELECT ci.*, p.name as product_name, p.price
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    WHERE ci.client_username = ?
  `).all(req.user.username);

  if (!items.length) return res.status(400).json({ error: 'Carrito vacío' });

  const total = items.reduce((sum, i) => sum + i.price * i.quantity, 0);
  const result = db.prepare(`
    INSERT INTO client_orders (client_username, items_json, total, payment_method, nequi_reference, delivery_date)
    VALUES (?,?,?,?,?,?)
  `).run(
    req.user.username,
    JSON.stringify(items.map(i => ({ id: i.product_id, name: i.product_name, price: i.price, qty: i.quantity }))),
    total,
    payment_method,
    nequi_reference || null,
    delivery_date || items[0]?.delivery_date || null
  );

  db.prepare('DELETE FROM cart_items WHERE client_username=?').run(req.user.username);
  const order = db.prepare('SELECT * FROM client_orders WHERE id=?').get(result.lastInsertRowid);
  res.status(201).json({ order });
});

// GET /api/cart/orders — admin list all client orders
router.get('/orders', adminAuth, (req, res) => {
  const orders = getDB().prepare('SELECT * FROM client_orders ORDER BY created_at DESC').all();
  res.json({ orders: orders.map(o => ({ ...o, items: JSON.parse(o.items_json) })) });
});

module.exports = router;
