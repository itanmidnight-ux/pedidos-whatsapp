'use strict';
const express = require('express');
const router  = express.Router();
const { clientAuth } = require('../middleware/auth');
const {
  parseOrderMessage, parseMultiItems, fuzzyProductMatch, extractAddress,
  isGreeting, isComplaint, isConfirmation, isDenial,
  hasOrderContent,
} = require('../services/llmParser');
const { getDB, withTransaction } = require('../db/database');

function sanitize(str, max = 500) {
  if (typeof str !== 'string') return null;
  return str.trim().slice(0, max).replace(/[<>]/g, '');
}

async function getPending(db, phone) {
  const { rows } = await db.query('SELECT * FROM pending_orders WHERE phone=$1', [phone]);
  return rows[0] || null;
}
async function savePending(db, phone, data) {
  const itemsJson = Array.isArray(data.items) && data.items.length ? JSON.stringify(data.items) : '[]';
  await db.query(`
    INSERT INTO pending_orders (phone,product_id,product_name,delivery_address,is_fiado,customer_name,wa_message,missing_field,pending_items)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
    ON CONFLICT(phone) DO UPDATE SET
      product_id=excluded.product_id, product_name=excluded.product_name,
      delivery_address=excluded.delivery_address, is_fiado=excluded.is_fiado,
      customer_name=excluded.customer_name, wa_message=excluded.wa_message,
      missing_field=excluded.missing_field, pending_items=excluded.pending_items,
      created_at=now_iso()
  `, [
    phone, data.product_id ?? null, data.product_name ?? null,
    data.delivery_address ?? null, data.is_fiado ? 1 : 0,
    data.customer_name ?? null, data.wa_message ?? null, data.missing_field ?? null,
    itemsJson,
  ]);
}
async function clearPending(db, phone) {
  await db.query('DELETE FROM pending_orders WHERE phone=$1', [phone]);
}
function getPendingItems(pending) {
  try { return JSON.parse(pending.pending_items || '[]'); } catch { return []; }
}

async function productListText(db) {
  const { rows } = await db.query('SELECT name, price FROM products WHERE available=1');
  return rows.map((p, i) => `  ${i + 1}. ${p.name} — $${Number(p.price).toLocaleString('es-CO')}`).join('\n');
}

// POST /api/chat/message — authenticated client sends a message, bot processes it
router.post('/message', clientAuth, async (req, res, next) => {
  try {
    const rawMessage = req.body.message;
    if (!rawMessage || typeof rawMessage !== 'string' || !rawMessage.trim())
      return res.status(400).json({ error: 'message requerido' });

    const message  = sanitize(rawMessage, 1000);
    const username = req.user.username;
    const phone    = `app:${username}`;
    const db       = getDB();

    // Ensure customer record exists
    const { rows: userRows } = await db.query('SELECT display_name, address FROM users WHERE username=$1', [username]);
    const name    = userRows[0]?.display_name || username;
    await db.query(`INSERT INTO customers (phone, name) VALUES ($1, $2)
      ON CONFLICT(phone) DO UPDATE SET name=excluded.name`, [phone, name]);

    const { rows: custRows } = await db.query('SELECT * FROM customers WHERE phone=$1', [phone]);
    const customer = custRows[0];
    const pending  = await getPending(db, phone);

    // ── Complaint ──────────────────────────────────────────────
    if (isComplaint(message)) {
      return res.json({ reply: '📋 Hemos registrado tu mensaje. Un colaborador lo revisará pronto. ¡Gracias por avisarnos!' });
    }

    // ── Greeting (no pending, no order content) ────────────────
    if (isGreeting(message) && !pending && !hasOrderContent(message)) {
      const { rows: prods } = await db.query('SELECT name, price FROM products WHERE available=1');
      const menu = prods.map((p, i) => `${i+1}. ${p.name} — $${Number(p.price).toLocaleString('es-CO')}`).join('\n');
      return res.json({
        reply: `¡Hola${name ? ' ' + name : ''}! 👋 Bienvenido a *Supermercado GO*.\n\n📦 *Productos disponibles:*\n${menu || '(sin productos)'}\n\nEscribe tu pedido con la dirección de entrega.`,
      });
    }

    // ── Pending: confirm product ───────────────────────────────
    if (pending?.missing_field === 'confirm_product') {
      if (isConfirmation(message)) {
        if (!pending.delivery_address) {
          await savePending(db, phone, { ...pending, missing_field: 'address' });
          return res.json({ reply: `Perfecto, anotamos *${pending.product_name}* 📦\n\n¿A qué dirección enviamos? 🏠` });
        }
        await clearPending(db, phone);
        return _createOrder(db, customer, pending, message, res);
      }
      if (isDenial(message)) {
        await clearPending(db, phone);
        return res.json({ reply: `Entendido. Elige el producto de esta lista:\n${await productListText(db)}` });
      }
      const { rows: products } = await db.query('SELECT * FROM products WHERE available=1');
      const match = fuzzyProductMatch(message, products);
      if (match && match.score === 0) {
        const upd = { ...pending, product_id: match.product.id, product_name: match.product.name,
          missing_field: pending.delivery_address ? null : 'address' };
        if (!pending.delivery_address) {
          await savePending(db, phone, upd);
          return res.json({ reply: `Anotamos *${match.product.name}* 📦\n\n¿A qué dirección enviamos? 🏠` });
        }
        await clearPending(db, phone);
        return _createOrder(db, customer, upd, message, res);
      }
      return res.json({ reply: `Por favor elige un producto de esta lista:\n${await productListText(db)}` });
    }

    // ── Pending: missing product ───────────────────────────────
    if (pending?.missing_field === 'product') {
      const { rows: products } = await db.query('SELECT * FROM products WHERE available=1');
      const match = fuzzyProductMatch(message, products);
      if (match) {
        const addr = pending.delivery_address || extractAddress(message);
        const data = { ...pending, product_id: match.product.id, product_name: match.product.name, delivery_address: addr };
        if (match.score > 0) {
          await savePending(db, phone, { ...data, missing_field: 'confirm_product' });
          return res.json({ reply: `¿Te refieres a *${match.product.name}*? Responde *sí* o *no*.` });
        }
        if (!addr) {
          await savePending(db, phone, { ...data, missing_field: 'address' });
          return res.json({ reply: `Anotamos *${match.product.name}* 📦\n\n¿A qué dirección enviamos? 🏠` });
        }
        await clearPending(db, phone);
        return _createOrder(db, customer, data, message, res);
      }
      return res.json({ reply: `No reconocí ese producto. Elige uno:\n${await productListText(db)}` });
    }

    // ── Pending: missing address ───────────────────────────────
    if (pending?.missing_field === 'address') {
      const addr = extractAddress(message) || (message.trim().length >= 3 ? message.trim() : null);
      if (addr) {
        await clearPending(db, phone);
        const items = getPendingItems(pending);
        if (items.length >= 2) return _createMultiOrder(db, customer, items, addr, message, res);
        return _createOrder(db, customer, { ...pending, delivery_address: addr }, message, res);
      }
      return res.json({ reply: '¿A qué dirección enviamos el pedido? Escribe la dirección completa.' });
    }

    // ── First turn: try multi-product ─────────────────────────
    const { rows: dbProducts } = await db.query('SELECT * FROM products WHERE available=1');
    const multiItems = parseMultiItems(message, dbProducts);
    if (multiItems) {
      const addr = extractAddress(message);
      if (addr) return _createMultiOrder(db, customer, multiItems, addr, message, res);
      const itemLines = multiItems.map(i => `📦 ${i.quantity}x ${i.product_name}`).join('\n');
      await savePending(db, phone, { items: multiItems, missing_field: 'address', wa_message: message });
      return res.json({ reply: `Anotamos tu pedido:\n${itemLines}\n\n¿A qué dirección enviamos? 🏠` });
    }

    // ── Parse single message ───────────────────────────────────
    let parsed;
    try { parsed = await parseOrderMessage(message); }
    catch (_) {
      parsed = { product_id: null, product_name: null,
        delivery_address: extractAddress(message), is_fiado: false,
        customer_name: null, confidence: 'low', needs_confirmation: false,
        needs_clarification: false, source: 'fallback', intent: null };
    }
    parsed.wa_message = message;

    if (!parsed.product_id) {
      await savePending(db, phone, { ...parsed, missing_field: 'product' });
      return res.json({ reply: `Hola! 👋 No identifiqué el producto.\n\nProductos disponibles:\n${await productListText(db)}\n\n¿Cuál deseas pedir?` });
    }

    if (parsed.needs_confirmation) {
      await savePending(db, phone, { ...parsed, missing_field: 'confirm_product' });
      return res.json({ reply: `¿Te refieres a *${parsed.product_name}*? Responde *sí* o *no*.` });
    }

    if (!parsed.delivery_address) {
      await savePending(db, phone, { ...parsed, missing_field: 'address' });
      return res.json({ reply: `Anotamos *${parsed.product_name}* 📦\n\n¿A qué dirección enviamos? 🏠` });
    }

    return _createOrder(db, customer, parsed, message, res);
  } catch (e) { next(e); }
});

async function _createOrder(db, customer, data, message, res) {
  const prod = data.product_id
    ? (await db.query('SELECT price FROM products WHERE id=$1', [data.product_id])).rows[0] : null;

  // orders + order_items en una sola transaccion -- antes el order_items
  // nunca se insertaba aca (solo en _createMultiOrder), asi que estos
  // pedidos de un solo producto quedaban invisibles para /analytics/products
  // (que solo lee order_items). Mismo fix ya aplicado en webhook.js.
  const orderId = await withTransaction(async (client) => {
    const { rows } = await client.query(`INSERT INTO orders
      (customer_id,product_id,product_name,product_price,delivery_address,is_fiado,wa_message,requested_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,now_iso()) RETURNING id`,
      [customer.id, data.product_id,
        sanitize(data.product_name, 200), prod?.price ?? null,
        sanitize(data.delivery_address, 300), data.is_fiado ? 1 : 0,
        sanitize(data.wa_message || message, 1000)]);
    const newId = rows[0].id;
    if (data.product_id) {
      await client.query('INSERT INTO order_items (order_id,product_id,product_name,product_price,quantity) VALUES ($1,$2,$3,$4,$5)',
        [newId, data.product_id, sanitize(data.product_name, 200), prod?.price ?? null, data.quantity || 1]);
    }
    return newId;
  });

  const { rows: orderRows } = await db.query('SELECT * FROM orders WHERE id=$1', [orderId]);
  const order = orderRows[0];
  const precio = order.product_price
    ? `$${Number(order.product_price).toLocaleString('es-CO')}` : 'A confirmar';

  return res.json({
    reply: `✅ *Pedido confirmado*\n\n📦 ${order.product_name}\n📍 ${order.delivery_address}\n💰 ${precio}\n\nPronto te confirmamos el envío. 🚚`,
    order_id: order.id,
  });
}

async function _createMultiOrder(db, customer, items, address, message, res) {
  const summary = items.map(i => `${i.quantity}x ${i.product_name}`).join(', ');
  const primary = items[0];
  const orderId = await withTransaction(async (client) => {
    const { rows } = await client.query(`INSERT INTO orders
      (customer_id,product_id,product_name,product_price,delivery_address,wa_message,requested_at)
      VALUES ($1,$2,$3,$4,$5,$6,now_iso()) RETURNING id`,
      [customer.id, primary.product_id, summary, primary.product_price, address, message]);
    const newId = rows[0].id;
    for (const it of items) {
      await client.query('INSERT INTO order_items (order_id,product_id,product_name,product_price,quantity) VALUES ($1,$2,$3,$4,$5)',
        [newId, it.product_id, it.product_name, it.product_price, it.quantity]);
    }
    return newId;
  });

  return res.json({
    reply: `✅ *Pedido recibido:*\n${items.map(i => `📦 ${i.quantity}x ${i.product_name}`).join('\n')}\n📍 ${address}\n\nPronto confirmamos el envío. 🚚`,
    order_id: orderId,
  });
}

module.exports = router;
