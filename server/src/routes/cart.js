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
  if (payment_method === 'nequi') {
    if (!nequi_reference || typeof nequi_reference !== 'string' || !nequi_reference.trim() || nequi_reference.length > 100)
      return res.status(400).json({ error: 'nequi_reference inválido (máx 100 chars)' });
  }

  const db = getDB();
  const items = db.prepare(`
    SELECT ci.*, p.name as product_name, p.price
    FROM cart_items ci
    JOIN products p ON p.id = ci.product_id
    WHERE ci.client_username = ?
  `).all(req.user.username);

  if (!items.length) return res.status(400).json({ error: 'Carrito vacío' });

  const total        = items.reduce((sum, i) => sum + i.price * i.quantity, 0);
  const finalDate    = delivery_date || items[0]?.delivery_date || null;
  const itemsSummary = items.map(i => `${i.quantity}x ${i.product_name}`).join(', ');
  const payLabel     = payment_method === 'nequi' ? 'Nequi' : 'Contra entrega';
  const safeRef      = nequi_reference ? nequi_reference.trim() : null;

  const clientUser = db.prepare('SELECT display_name, address FROM users WHERE username=?').get(req.user.username);
  const clientName = clientUser?.display_name || req.user.username;
  const clientAddr = clientUser?.address || '';
  const appPhone   = `app:${req.user.username}`;

  const doCheckout = db.transaction(() => {
    const existingCust = db.prepare('SELECT id FROM customers WHERE phone=?').get(appPhone);
    let customerId;
    if (existingCust) {
      db.prepare('UPDATE customers SET name=? WHERE id=?').run(clientName, existingCust.id);
      customerId = existingCust.id;
    } else {
      customerId = db.prepare('INSERT INTO customers (phone, name) VALUES (?,?)').run(appPhone, clientName).lastInsertRowid;
    }

    const orderResult = db.prepare(`
      INSERT INTO orders (customer_id, product_name, delivery_address, wa_message, requested_at, status, is_fiado)
      VALUES (?,?,?,?,datetime('now','localtime'),'pending',0)
    `).run(customerId, itemsSummary, clientAddr,
      `[App] ${clientName} • ${payLabel}${safeRef ? ' ref:' + safeRef : ''}`);
    const mainOrderId = orderResult.lastInsertRowid;

    for (const item of items) {
      db.prepare('INSERT INTO order_items (order_id, product_id, product_name, product_price, quantity) VALUES (?,?,?,?,?)')
        .run(mainOrderId, item.product_id, item.product_name, item.price, item.quantity);
    }

    const result = db.prepare(`
      INSERT INTO client_orders (client_username, items_json, total, payment_method, nequi_reference, delivery_date)
      VALUES (?,?,?,?,?,?)
    `).run(
      req.user.username,
      JSON.stringify(items.map(i => ({ id: i.product_id, name: i.product_name, price: i.price, qty: i.quantity }))),
      total, payment_method, safeRef, finalDate
    );

    db.prepare('DELETE FROM cart_items WHERE client_username=?').run(req.user.username);
    return db.prepare('SELECT * FROM client_orders WHERE id=?').get(result.lastInsertRowid);
  });

  try {
    const order = doCheckout();
    res.status(201).json({ order });
  } catch {
    res.status(500).json({ error: 'Error procesando pedido — intenta de nuevo' });
  }
});

// GET /api/cart/orders — admin list all client orders
router.get('/orders', adminAuth, (req, res) => {
  const orders = getDB().prepare('SELECT * FROM client_orders ORDER BY created_at DESC').all();
  res.json({ orders: orders.map(o => ({ ...o, items: JSON.parse(o.items_json) })) });
});

module.exports = router;
