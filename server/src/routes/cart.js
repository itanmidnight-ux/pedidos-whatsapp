'use strict';
const express = require('express');
const router  = express.Router();
const { clientAuth, adminAuth } = require('../middleware/auth');
const { getDB, withTransaction } = require('../db/database');

// GET /api/cart — get my cart items
router.get('/', clientAuth, async (req, res, next) => {
  try {
    const { rows: items } = await getDB().query(`
      SELECT ci.*, p.name as product_name, p.price, p.available
      FROM cart_items ci
      JOIN products p ON p.id = ci.product_id
      WHERE ci.client_username = $1
      ORDER BY ci.created_at ASC
    `, [req.user.username]);
    res.json({ items });
  } catch (e) { next(e); }
});

// POST /api/cart — add/update item
router.post('/', clientAuth, async (req, res, next) => {
  try {
    const { product_id, quantity, delivery_date } = req.body;
    if (!product_id || !quantity || quantity < 1)
      return res.status(400).json({ error: 'product_id y quantity requeridos' });
    const db = getDB();
    const { rows: prodRows } = await db.query('SELECT id FROM products WHERE id=$1 AND available=1', [product_id]);
    if (!prodRows[0]) return res.status(404).json({ error: 'Producto no disponible' });
    const { rows: existingRows } = await db.query(
      'SELECT id FROM cart_items WHERE client_username=$1 AND product_id=$2', [req.user.username, product_id]
    );
    const existing = existingRows[0];
    if (existing) {
      await db.query('UPDATE cart_items SET quantity=$1, delivery_date=$2 WHERE id=$3',
        [quantity, delivery_date || null, existing.id]);
    } else {
      await db.query('INSERT INTO cart_items (client_username, product_id, quantity, delivery_date) VALUES ($1,$2,$3,$4)',
        [req.user.username, product_id, quantity, delivery_date || null]);
    }
    res.json({ ok: true });
  } catch (e) { next(e); }
});

// DELETE /api/cart/:product_id — remove item
router.delete('/:product_id', clientAuth, async (req, res, next) => {
  try {
    await getDB().query('DELETE FROM cart_items WHERE client_username=$1 AND product_id=$2',
      [req.user.username, req.params.product_id]);
    res.json({ ok: true });
  } catch (e) { next(e); }
});

// DELETE /api/cart — clear cart
router.delete('/', clientAuth, async (req, res, next) => {
  try {
    await getDB().query('DELETE FROM cart_items WHERE client_username=$1', [req.user.username]);
    res.json({ ok: true });
  } catch (e) { next(e); }
});

// POST /api/cart/checkout — place order from cart
router.post('/checkout', clientAuth, async (req, res, next) => {
  try {
    const { payment_method, nequi_reference, delivery_date } = req.body;
    if (!['nequi', 'contra_entrega'].includes(payment_method))
      return res.status(400).json({ error: 'payment_method debe ser nequi o contra_entrega' });
    if (payment_method === 'nequi') {
      if (!nequi_reference || typeof nequi_reference !== 'string' || !nequi_reference.trim() || nequi_reference.length > 100)
        return res.status(400).json({ error: 'nequi_reference inválido (máx 100 chars)' });
    }

    const db = getDB();
    const { rows: items } = await db.query(`
      SELECT ci.*, p.name as product_name, p.price
      FROM cart_items ci
      JOIN products p ON p.id = ci.product_id
      WHERE ci.client_username = $1
    `, [req.user.username]);

    if (!items.length) return res.status(400).json({ error: 'Carrito vacío' });

    const total        = items.reduce((sum, i) => sum + i.price * i.quantity, 0);
    const finalDate     = delivery_date || items[0]?.delivery_date || null;
    const itemsSummary = items.map(i => `${i.quantity}x ${i.product_name}`).join(', ');
    const payLabel     = payment_method === 'nequi' ? 'Nequi' : 'Contra entrega';
    const safeRef      = nequi_reference ? nequi_reference.trim() : null;

    const { rows: clientRows } = await db.query('SELECT display_name, address, phone FROM users WHERE username=$1', [req.user.username]);
    const clientUser = clientRows[0];
    const clientName = clientUser?.display_name || req.user.username;
    const clientAddr = clientUser?.address || '';
    // Telefono real del cliente (columna users.phone, pedida en el registro)
    // -- antes se usaba un placeholder falso "app:<username>" que dejaba al
    // trabajador sin forma de llamar o escribirle de verdad por WhatsApp.
    // Fallback solo para cuentas viejas creadas antes de pedir el celular.
    const realPhone  = clientUser?.phone || `app:${req.user.username}`;

    const order = await withTransaction(async (client) => {
      const { rows: existingCustRows } = await client.query('SELECT id FROM customers WHERE phone=$1', [realPhone]);
      const existingCust = existingCustRows[0];
      let customerId;
      if (existingCust) {
        await client.query('UPDATE customers SET name=$1 WHERE id=$2', [clientName, existingCust.id]);
        customerId = existingCust.id;
      } else {
        const { rows } = await client.query('INSERT INTO customers (phone, name) VALUES ($1,$2) RETURNING id', [realPhone, clientName]);
        customerId = rows[0].id;
      }

      const { rows: orderRows } = await client.query(`
        INSERT INTO orders (customer_id, product_name, delivery_address, wa_message, requested_at, status, is_fiado)
        VALUES ($1,$2,$3,$4,now_iso(),'pending',0) RETURNING id
      `, [customerId, itemsSummary, clientAddr, `[App] ${clientName} • ${payLabel}${safeRef ? ' ref:' + safeRef : ''}`]);
      const mainOrderId = orderRows[0].id;

      for (const item of items) {
        await client.query('INSERT INTO order_items (order_id, product_id, product_name, product_price, quantity) VALUES ($1,$2,$3,$4,$5)',
          [mainOrderId, item.product_id, item.product_name, item.price, item.quantity]);
      }

      const { rows: coRows } = await client.query(`
        INSERT INTO client_orders (client_username, items_json, total, payment_method, nequi_reference, delivery_date)
        VALUES ($1,$2,$3,$4,$5,$6) RETURNING *
      `, [
        req.user.username,
        JSON.stringify(items.map(i => ({ id: i.product_id, name: i.product_name, price: i.price, qty: i.quantity }))),
        total, payment_method, safeRef, finalDate,
      ]);

      await client.query('DELETE FROM cart_items WHERE client_username=$1', [req.user.username]);
      return coRows[0];
    });

    res.status(201).json({ order });
  } catch (e) {
    res.status(500).json({ error: 'Error procesando pedido — intenta de nuevo' });
  }
});

// GET /api/cart/orders — admin list all client orders
router.get('/orders', adminAuth, async (req, res, next) => {
  try {
    const { rows: orders } = await getDB().query('SELECT * FROM client_orders ORDER BY created_at DESC');
    res.json({ orders: orders.map(o => ({ ...o, items: JSON.parse(o.items_json) })) });
  } catch (e) { next(e); }
});

module.exports = router;
