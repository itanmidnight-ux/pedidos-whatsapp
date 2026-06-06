const express = require('express');
const router  = express.Router();
const { apiKeyAuth } = require('../middleware/auth');
const {
  parseOrderMessage, parseMultiItems, fuzzyProductMatch, extractAddress,
  isGreeting, isComplaint, isConfirmation, isDenial,
  hasOrderContent, findAmbiguousCategory,
} = require('../services/llmParser');
const { getDB } = require('../db/database');

function sanitize(str, max = 500) {
  if (typeof str !== 'string') return null;
  return str.trim().slice(0, max).replace(/[<>]/g, '');
}

// ── Pending orders helpers ────────────────────────────────────
function getPending(db, phone) {
  return db.prepare('SELECT * FROM pending_orders WHERE phone=?').get(phone);
}
function savePending(db, phone, data) {
  db.prepare(`
    INSERT INTO pending_orders (phone,product_id,product_name,delivery_address,is_fiado,customer_name,wa_message,missing_field)
    VALUES (?,?,?,?,?,?,?,?)
    ON CONFLICT(phone) DO UPDATE SET
      product_id=excluded.product_id, product_name=excluded.product_name,
      delivery_address=excluded.delivery_address, is_fiado=excluded.is_fiado,
      customer_name=excluded.customer_name, wa_message=excluded.wa_message,
      missing_field=excluded.missing_field,
      created_at=datetime('now','localtime')
  `).run(
    phone, data.product_id ?? null, data.product_name ?? null,
    data.delivery_address ?? null, data.is_fiado ? 1 : 0,
    data.customer_name ?? null, data.wa_message ?? null, data.missing_field ?? null
  );
}
function clearPending(db, phone) {
  db.prepare('DELETE FROM pending_orders WHERE phone=?').run(phone);
}

// ── Helpers de texto ─────────────────────────────────────────
function productListText(db) {
  return db.prepare('SELECT name FROM products WHERE available=1').all()
    .map((p, i) => `  ${i + 1}. ${p.name}`).join('\n');
}

function confirmationText(order) {
  const fiado  = order.is_fiado ? '\n⚠️ *Pago diferido registrado*' : '';
  const precio = order.product_price
    ? `$${Number(order.product_price).toLocaleString('es-CO')}` : 'A confirmar';
  return `✅ *Pedido confirmado*\n\n📦 ${order.product_name}\n📍 ${order.delivery_address}\n💰 ${precio}${fiado}\n\nPronto te confirmamos el envío. 🚚`;
}

// ── Marcar mensaje como alerta ────────────────────────────────
function flagLastMessage(db, phone, reason) {
  db.prepare(`
    UPDATE messages SET flagged=1, flag_reason=?
    WHERE phone=? AND direction='inbound'
    ORDER BY created_at DESC LIMIT 1
  `).run(reason, phone);
}

// ── Ruta principal ────────────────────────────────────────────
router.post('/message', apiKeyAuth, async (req, res) => {
  const rawPhone   = req.body.phone;
  const rawMessage = req.body.message;
  const rawName    = req.body.name;
  const rawTs      = req.body.timestamp;

  if (!rawPhone || !/^\d{7,15}$/.test(String(rawPhone).trim()))
    return res.status(400).json({ error: 'phone inválido' });
  if (!rawMessage || typeof rawMessage !== 'string' || !rawMessage.trim())
    return res.status(400).json({ error: 'message requerido' });

  const phone     = String(rawPhone).trim();
  const message   = sanitize(rawMessage, 1000);
  const name      = rawName ? sanitize(rawName, 100) : null;
  const timestamp = rawTs && !isNaN(Date.parse(rawTs))
    ? new Date(rawTs).toISOString() : new Date().toISOString();
  const db = getDB();

  // Guardar cliente y mensaje
  db.prepare(`INSERT INTO customers (phone, name) VALUES (?, ?)
    ON CONFLICT(phone) DO UPDATE SET name = COALESCE(excluded.name, name)`)
    .run(phone, name);
  const msgRow = db.prepare(`INSERT INTO messages (phone, customer_name, content, direction, sent)
    VALUES (?, ?, ?, 'inbound', 1)`)
    .run(phone, name, message);

  const customer = db.prepare('SELECT * FROM customers WHERE phone=?').get(phone);
  const pending  = getPending(db, phone);

  // ── Detectar queja / reclamo ──────────────────────────────
  if (isComplaint(message)) {
    flagLastMessage(db, phone, 'reclamo');
    return res.json({
      success: false,
      flagged: true,
      reply: '📋 Hemos registrado tu mensaje como importante. Un colaborador lo revisará pronto. ¡Gracias por avisarnos!',
    });
  }

  // ── Saludo sin pedido (solo si el mensaje NO contiene una orden) ────
  if (isGreeting(message) && !pending && !hasOrderContent(message)) {
    const products = db.prepare('SELECT * FROM products WHERE available=1').all();
    const menuLines = products.map((p, i) => `  ${i+1}. ${p.name} — $${Number(p.price).toLocaleString('es-CO')}`).join('\n');
    return res.json({
      success: false,
      reply: `¡Hola! 👋 Bienvenido a *Concentrados Monserrath*.\n\n📦 *Productos disponibles:*\n${menuLines || '  (sin productos)'}\n\nEscríbenos tu pedido con la dirección de entrega.`,
    });
  }

  // ── Manejo de pending: confirmación de producto ───────────
  if (pending?.missing_field === 'confirm_product') {
    if (isConfirmation(message)) {
      // Usuario confirmó el producto sugerido
      const updatedPending = {
        ...pending,
        missing_field: pending.delivery_address ? null : 'address',
      };
      if (!pending.delivery_address) {
        savePending(db, phone, updatedPending);
        return res.json({
          success: false, pending: true,
          reply: `Perfecto, anotamos *${pending.product_name}* 📦\n\n¿A qué dirección enviamos? 🏠`,
        });
      }
      // Tiene todo — crear pedido
      clearPending(db, phone);
      return createOrder(db, customer, pending, message, timestamp, res);
    }

    if (isDenial(message)) {
      clearPending(db, phone);
      return res.json({
        success: false, pending: true,
        reply: `Entendido. Por favor elige el producto de esta lista:\n${productListText(db)}`,
      });
    }

    // Cliente respondió otra cosa — intentar extraer producto de la respuesta
    const products = db.prepare('SELECT * FROM products WHERE available=1').all();
    const match    = fuzzyProductMatch(message, products);
    if (match && match.score === 0) {
      const updatedPending = {
        ...pending, product_id: match.product.id,
        product_name: match.product.name, missing_field: pending.delivery_address ? null : 'address',
      };
      if (!pending.delivery_address) {
        savePending(db, phone, updatedPending);
        return res.json({
          success: false, pending: true,
          reply: `Anotamos *${match.product.name}* 📦\n\n¿A qué dirección enviamos? 🏠`,
        });
      }
      clearPending(db, phone);
      return createOrder(db, customer, updatedPending, message, timestamp, res);
    }

    return res.json({
      success: false, pending: true,
      reply: `Por favor elige un producto de esta lista:\n${productListText(db)}`,
    });
  }

  // ── Manejo de pending: falta producto ────────────────────
  if (pending?.missing_field === 'product') {
    const products = db.prepare('SELECT * FROM products WHERE available=1').all();
    const match    = fuzzyProductMatch(message, products);
    if (match) {
      const hasAddr = !!(pending.delivery_address || extractAddress(message));
      const addr    = pending.delivery_address || extractAddress(message);
      const data    = { ...pending, product_id: match.product.id, product_name: match.product.name, delivery_address: addr };

      if (match.score > 0) {
        // Match difuso — confirmar con el cliente
        savePending(db, phone, { ...data, missing_field: 'confirm_product' });
        return res.json({
          success: false, pending: true,
          reply: `¿Te refieres a *${match.product.name}*? Responde *sí* o *no*.`,
        });
      }
      if (!hasAddr) {
        savePending(db, phone, { ...data, missing_field: 'address' });
        return res.json({
          success: false, pending: true,
          reply: `Anotamos *${match.product.name}* 📦\n\n¿A qué dirección enviamos? 🏠`,
        });
      }
      clearPending(db, phone);
      return createOrder(db, customer, data, message, timestamp, res);
    }
    return res.json({
      success: false, pending: true,
      reply: `No reconocí ese producto. Elige uno:\n${productListText(db)}`,
    });
  }

  // ── Manejo de pending: falta dirección ───────────────────
  if (pending?.missing_field === 'address') {
    const addr = extractAddress(message) || (message.trim().length >= 3 ? message.trim() : null);
    if (addr) {
      clearPending(db, phone);
      return createOrder(db, customer, { ...pending, delivery_address: addr }, message, timestamp, res);
    }
    return res.json({
      success: false, pending: true,
      reply: '¿A qué dirección enviamos el pedido? Escribe la dirección completa.',
    });
  }

  // ── Primer turno: intentar multi-producto ────────────────
  const dbProducts = db.prepare('SELECT * FROM products WHERE available=1').all();
  const multiItems = parseMultiItems(message, dbProducts);
  if (multiItems && extractAddress(message)) {
    const addr = extractAddress(message);
    return createMultiOrder(db, customer, multiItems, addr, message, timestamp, res);
  }

  // ── Parsear mensaje único ─────────────────────────────────
  const parsed    = await parseOrderMessage(message);
  parsed.wa_message = message;

  // Detectar pedido con producto de no_fiado + fiado solicitado
  if (parsed.product_id && parsed.is_fiado) {
    const prod = db.prepare('SELECT no_fiado FROM products WHERE id=?').get(parsed.product_id);
    if (prod?.no_fiado) {
      flagLastMessage(db, phone, 'fiado_bloqueado');
      return res.json({
        success: false, flagged: true,
        reply: `⚠️ El producto *${parsed.product_name}* no se fía. Si tienes alguna consulta, comunícate con nosotros directamente.`,
      });
    }
  }

  const hasProduct = !!parsed.product_id;
  const hasAddress = !!parsed.delivery_address;

  // Producto con coincidencia media → confirmar antes de continuar
  if (hasProduct && parsed.needs_confirmation) {
    savePending(db, phone, {
      ...parsed, wa_message: message,
      missing_field: 'confirm_product',
    });
    return res.json({
      success: false, pending: true,
      reply: `¿Te refieres a *${parsed.product_name}*? Responde *sí* o *no*.`,
    });
  }

  if (!hasProduct) {
    // Categoría ambigua: producto parcialmente identificado, múltiples opciones
    if (parsed.needs_clarification && Array.isArray(parsed.ambiguous_candidates) && parsed.ambiguous_candidates.length >= 2) {
      const kw       = parsed.ambiguous_keyword || 'producto';
      const kwCap    = kw.charAt(0).toUpperCase() + kw.slice(1);
      const optLines = parsed.ambiguous_candidates.map((p, i) => `  ${i+1}. ${p.name}`).join('\n');
      savePending(db, phone, { ...parsed, wa_message: message, missing_field: 'product' });
      return res.json({
        success: false, pending: true,
        reply: `¿${kwCap} de qué?\n${optLines}\n\n¿Cuál deseas?`,
      });
    }
    savePending(db, phone, { ...parsed, wa_message: message, missing_field: 'product' });
    return res.json({
      success: false, pending: true,
      reply: `Hola! 👋 No identifiqué el producto.\n\nProductos disponibles:\n${productListText(db)}\n\n¿Cuál deseas pedir?`,
    });
  }

  if (!hasAddress) {
    savePending(db, phone, { ...parsed, wa_message: message, missing_field: 'address' });
    return res.json({
      success: false, pending: true,
      reply: `Anotamos *${parsed.product_name}* 📦\n\n¿A qué dirección enviamos? 🏠`,
    });
  }

  return createOrder(db, customer, parsed, message, timestamp, res);
});

function createOrder(db, customer, data, message, timestamp, res) {
  const prod = data.product_id
    ? db.prepare('SELECT price FROM products WHERE id=?').get(data.product_id) : null;

  const ins = db.prepare(`INSERT INTO orders
    (customer_id,product_id,product_name,product_price,delivery_address,is_fiado,wa_message,requested_at)
    VALUES (?,?,?,?,?,?,?,?)`)
    .run(
      customer.id, data.product_id,
      sanitize(data.product_name, 200),
      prod?.price ?? null,
      sanitize(data.delivery_address, 300),
      data.is_fiado ? 1 : 0,
      sanitize(data.wa_message || message, 1000),
      timestamp
    );

  const orderId = ins.lastInsertRowid;

  // Insertar items si vienen del multi-parser
  if (Array.isArray(data.items) && data.items.length) {
    const itemIns = db.prepare('INSERT INTO order_items (order_id,product_id,product_name,product_price,quantity) VALUES (?,?,?,?,?)');
    for (const it of data.items) itemIns.run(orderId, it.product_id, it.product_name, it.product_price, it.quantity || 1);
  }

  const order = db.prepare('SELECT * FROM orders WHERE id=?').get(orderId);
  if (order.is_fiado) {
    db.prepare(`UPDATE messages SET flagged=1, flag_reason='fiado_pedido'
      WHERE phone=? AND direction='inbound' ORDER BY created_at DESC LIMIT 1`)
      .run(customer.phone);
  }
  res.json({ success: true, order, reply: confirmationText(order) });
}

function createMultiOrder(db, customer, items, address, message, timestamp, res) {
  const summary = items.map(i => `${i.quantity}x ${i.product_name}`).join(', ');
  const primary = items[0];
  const ins = db.prepare(`INSERT INTO orders
    (customer_id,product_id,product_name,product_price,delivery_address,wa_message,requested_at)
    VALUES (?,?,?,?,?,?,?)`)
    .run(customer.id, primary.product_id, summary, primary.product_price, address, message, timestamp);

  const orderId = ins.lastInsertRowid;
  const itemIns = db.prepare('INSERT INTO order_items (order_id,product_id,product_name,product_price,quantity) VALUES (?,?,?,?,?)');
  for (const it of items) itemIns.run(orderId, it.product_id, it.product_name, it.product_price, it.quantity);

  const order = db.prepare('SELECT * FROM orders WHERE id=?').get(orderId);
  res.json({
    success: true, order,
    reply: `✅ *Pedido recibido:*\n${items.map(i => `📦 ${i.quantity}x ${i.product_name}`).join('\n')}\n📍 ${address}\n\nPronto confirmamos el envío.`,
  });
}

module.exports = router;
