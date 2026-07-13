const express = require('express');
const router  = express.Router();
const { apiKeyAuth, verifyWebhookSignature } = require('../middleware/auth');
const {
  parseOrderMessage, parseMultiItems, fuzzyProductMatch, extractAddress,
  isGreeting, isClosing, isComplaint, isConfirmation, isDenial,
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
  const itemsJson = Array.isArray(data.items) && data.items.length ? JSON.stringify(data.items) : '[]';
  db.prepare(`
    INSERT INTO pending_orders (phone,product_id,product_name,delivery_address,is_fiado,customer_name,wa_message,missing_field,pending_items)
    VALUES (?,?,?,?,?,?,?,?,?)
    ON CONFLICT(phone) DO UPDATE SET
      product_id=excluded.product_id, product_name=excluded.product_name,
      delivery_address=excluded.delivery_address, is_fiado=excluded.is_fiado,
      customer_name=excluded.customer_name, wa_message=excluded.wa_message,
      missing_field=excluded.missing_field,
      pending_items=excluded.pending_items,
      created_at=datetime('now','localtime')
  `).run(
    phone, data.product_id ?? null, data.product_name ?? null,
    data.delivery_address ?? null, data.is_fiado ? 1 : 0,
    data.customer_name ?? null, data.wa_message ?? null, data.missing_field ?? null,
    itemsJson
  );
}

function getPendingItems(pending) {
  try { return JSON.parse(pending.pending_items || '[]'); } catch { return []; }
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

// ── Encolar respuesta del bot como mensaje outbound ──────────
function queueBotReply(db, phone, content) {
  if (!content || !phone) return;
  try {
    const cust = db.prepare('SELECT name FROM customers WHERE phone=?').get(phone);
    db.prepare(`INSERT INTO messages (phone, customer_name, content, direction, sent, type)
      VALUES (?, ?, ?, 'outbound', 0, 'bot')`)
      .run(phone, cust?.name ?? null, String(content).slice(0, 2000));
  } catch (_) {}
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
router.post('/message', apiKeyAuth, verifyWebhookSignature, async (req, res) => {
  const rawPhone     = req.body.phone;
  const rawMessage   = req.body.message;
  const rawName      = req.body.name;
  const rawTs        = req.body.timestamp;
  const rawMediaType = req.body.media_type;  // 'audio' | 'image' | undefined
  const rawMediaUrl  = req.body.media_url;   // filename stored on disk
  const rawJid       = req.body.jid;         // JID real de WhatsApp (@s.whatsapp.net o @lid)

  if (!rawPhone || !/^\d{7,15}$/.test(String(rawPhone).trim()))
    return res.status(400).json({ error: 'phone inválido' });
  if (!rawMessage || typeof rawMessage !== 'string' || !rawMessage.trim())
    return res.status(400).json({ error: 'message requerido' });

  const phone     = String(rawPhone).trim();
  const message   = sanitize(rawMessage, 1000);
  const name      = rawName ? sanitize(rawName, 100) : null;
  const jid       = rawJid ? sanitize(rawJid, 100) : null;
  const timestamp = rawTs && !isNaN(Date.parse(rawTs))
    ? new Date(rawTs).toISOString() : new Date().toISOString();
  const db = getDB();

  // Guardar cliente, jid real (para poder responderle) y profile pic si viene
  const picUrl = req.body.profile_pic_url || null;
  db.prepare(`INSERT INTO customers (phone, name, profile_pic_url, wa_jid) VALUES (?, ?, ?, ?)
    ON CONFLICT(phone) DO UPDATE SET
      name = COALESCE(excluded.name, name),
      profile_pic_url = COALESCE(excluded.profile_pic_url, profile_pic_url),
      wa_jid = COALESCE(excluded.wa_jid, wa_jid)`)
    .run(phone, name, picUrl, jid);

  // Mensaje de media — guardar directo, sin NLP
  if (rawMediaType && rawMediaUrl) {
    const caption = rawMediaType === 'audio' ? '🎵 Mensaje de voz' : '📷 Imagen';
    db.prepare(`INSERT INTO messages (phone, customer_name, content, direction, sent, media_type, media_url)
      VALUES (?, ?, ?, 'inbound', 1, ?, ?)`)
      .run(phone, name, caption, rawMediaType, rawMediaUrl);
    const ackMsg = rawMediaType === 'audio'
      ? '✅ Tu mensaje de voz fue recibido. Un colaborador te responderá pronto.'
      : '✅ Imagen recibida. Un colaborador la revisará pronto.';
    queueBotReply(db, phone, ackMsg);
    return res.json({ success: true, media: true });
  }

  db.prepare(`INSERT INTO messages (phone, customer_name, content, direction, sent)
    VALUES (?, ?, ?, 'inbound', 1)`)
    .run(phone, name, message);

  const customer = db.prepare('SELECT * FROM customers WHERE phone=?').get(phone);
  const pending  = getPending(db, phone);

  // ── Detectar queja / reclamo ──────────────────────────────
  if (isComplaint(message)) {
    flagLastMessage(db, phone, 'reclamo');
    const reply = '📋 Hemos registrado tu mensaje como importante. Un colaborador lo revisará pronto. ¡Gracias por avisarnos!';
    queueBotReply(db, phone, reply);
    return res.json({ success: false, flagged: true });
  }

  // ── Saludo sin pedido (solo si el mensaje NO contiene una orden) ────
  if (isGreeting(message) && !pending && !hasOrderContent(message)) {
    const products = db.prepare('SELECT * FROM products WHERE available=1').all();
    const menuLines = products.map((p, i) => `  ${i+1}. ${p.name} — $${Number(p.price).toLocaleString('es-CO')}`).join('\n');
    const reply = `¡Hola! 👋 Bienvenido a *Concentrados Monserrath*.\n\n📦 *Productos disponibles:*\n${menuLines || '  (sin productos)'}\n\nEscríbenos tu pedido con la dirección de entrega.`;
    queueBotReply(db, phone, reply);
    return res.json({ success: false });
  }

  // ── Cierre/agradecimiento sin pedido pendiente -- responder amable y
  // NO reabrir el flujo de pedido (antes esto caia al fallback de "no
  // identifiqué el producto" y volvia a preguntar que querian pedir) ────
  if (isClosing(message) && !pending && !hasOrderContent(message)) {
    queueBotReply(db, phone, '¡Con gusto! 😊 Cualquier cosa que necesites, aquí estamos.');
    return res.json({ success: false });
  }

  // ── Manejo de pending: confirmación de producto ───────────
  if (pending?.missing_field === 'confirm_product') {
    if (isConfirmation(message)) {
      const updatedPending = {
        ...pending,
        missing_field: pending.delivery_address ? null : 'address',
      };
      if (!pending.delivery_address) {
        savePending(db, phone, updatedPending);
        const reply = `Perfecto, anotamos *${pending.product_name}* 📦\n\n¿A qué dirección enviamos? 🏠`;
        queueBotReply(db, phone, reply);
        return res.json({ success: false, pending: true });
      }
      clearPending(db, phone);
      return createOrder(db, customer, pending, message, timestamp, res);
    }

    if (isDenial(message)) {
      clearPending(db, phone);
      const reply = `Entendido. Por favor elige el producto de esta lista:\n${productListText(db)}`;
      queueBotReply(db, phone, reply);
      return res.json({ success: false, pending: true });
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
        const reply = `Anotamos *${match.product.name}* 📦\n\n¿A qué dirección enviamos? 🏠`;
        queueBotReply(db, phone, reply);
        return res.json({ success: false, pending: true });
      }
      clearPending(db, phone);
      return createOrder(db, customer, updatedPending, message, timestamp, res);
    }

    const replyFallback = `Por favor elige un producto de esta lista:\n${productListText(db)}`;
    queueBotReply(db, phone, replyFallback);
    return res.json({ success: false, pending: true });
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
        savePending(db, phone, { ...data, missing_field: 'confirm_product' });
        const reply = `¿Te refieres a *${match.product.name}*? Responde *sí* o *no*.`;
        queueBotReply(db, phone, reply);
        return res.json({ success: false, pending: true });
      }
      if (!hasAddr) {
        savePending(db, phone, { ...data, missing_field: 'address' });
        const reply = `Anotamos *${match.product.name}* 📦\n\n¿A qué dirección enviamos? 🏠`;
        queueBotReply(db, phone, reply);
        return res.json({ success: false, pending: true });
      }
      clearPending(db, phone);
      return createOrder(db, customer, data, message, timestamp, res);
    }
    const reply = `No reconocí ese producto. Elige uno:\n${productListText(db)}`;
    queueBotReply(db, phone, reply);
    return res.json({ success: false, pending: true });
  }

  // ── Manejo de pending: falta dirección ───────────────────
  if (pending?.missing_field === 'address') {
    const addr = extractAddress(message) || (message.trim().length >= 3 ? message.trim() : null);
    if (addr) {
      clearPending(db, phone);
      const pendingItems = getPendingItems(pending);
      if (pendingItems.length >= 2) {
        return createMultiOrder(db, customer, pendingItems, addr, pending.wa_message || message, timestamp, res);
      }
      return createOrder(db, customer, { ...pending, delivery_address: addr }, message, timestamp, res);
    }
    const reply = '¿A qué dirección enviamos el pedido? Escribe la dirección completa.';
    queueBotReply(db, phone, reply);
    return res.json({ success: false, pending: true });
  }

  // ── Primer turno: intentar multi-producto ────────────────
  const dbProducts = db.prepare('SELECT * FROM products WHERE available=1').all();
  const multiItems = parseMultiItems(message, dbProducts);
  if (multiItems) {
    const addr = extractAddress(message);
    if (addr) return createMultiOrder(db, customer, multiItems, addr, message, timestamp, res);
    // Multi-items detected but no address — save and ask
    savePending(db, phone, { items: multiItems, missing_field: 'address', wa_message: message });
    const itemLines = multiItems.map(i => `📦 ${i.quantity}x ${i.product_name}`).join('\n');
    const reply = `Anotamos tu pedido:\n${itemLines}\n\n¿A qué dirección enviamos? 🏠`;
    queueBotReply(db, phone, reply);
    return res.json({ success: false, pending: true });
  }

  // ── Parsear mensaje único ─────────────────────────────────
  let parsed;
  try {
    parsed = await parseOrderMessage(message);
  } catch (_) {
    parsed = { product_id: null, product_name: null, delivery_address: extractAddress(message),
      is_fiado: false, customer_name: null, confidence: 'low',
      needs_confirmation: false, needs_clarification: false,
      ambiguous_keyword: null, ambiguous_candidates: null,
      source: 'fallback', intent: null, quantity: null, unit: null };
  }
  parsed.wa_message = message;

  // Detectar pedido con producto de no_fiado + fiado solicitado
  if (parsed.product_id && parsed.is_fiado) {
    const prod = db.prepare('SELECT no_fiado FROM products WHERE id=?').get(parsed.product_id);
    if (prod?.no_fiado) {
      flagLastMessage(db, phone, 'fiado_bloqueado');
      const reply = `⚠️ El producto *${parsed.product_name}* no se fía. Si tienes alguna consulta, comunícate con nosotros directamente.`;
      queueBotReply(db, phone, reply);
      return res.json({ success: false, flagged: true });
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
    const reply = `¿Te refieres a *${parsed.product_name}*? Responde *sí* o *no*.`;
    queueBotReply(db, phone, reply);
    return res.json({ success: false, pending: true });
  }

  if (!hasProduct) {
    // Categoría ambigua: producto parcialmente identificado, múltiples opciones
    if (parsed.needs_clarification && Array.isArray(parsed.ambiguous_candidates) && parsed.ambiguous_candidates.length >= 2) {
      const kw       = parsed.ambiguous_keyword || 'producto';
      const kwCap    = kw.charAt(0).toUpperCase() + kw.slice(1);
      const optLines = parsed.ambiguous_candidates.map((p, i) => `  ${i+1}. ${p.name}`).join('\n');
      savePending(db, phone, { ...parsed, wa_message: message, missing_field: 'product' });
      const reply = `¿${kwCap} de qué?\n${optLines}\n\n¿Cuál deseas?`;
      queueBotReply(db, phone, reply);
      return res.json({ success: false, pending: true });
    }
    savePending(db, phone, { ...parsed, wa_message: message, missing_field: 'product' });
    const reply = `Hola! 👋 No identifiqué el producto.\n\nProductos disponibles:\n${productListText(db)}\n\n¿Cuál deseas pedir?`;
    queueBotReply(db, phone, reply);
    return res.json({ success: false, pending: true });
  }

  if (!hasAddress) {
    savePending(db, phone, { ...parsed, wa_message: message, missing_field: 'address' });
    const reply = `Anotamos *${parsed.product_name}* 📦\n\n¿A qué dirección enviamos? 🏠`;
    queueBotReply(db, phone, reply);
    return res.json({ success: false, pending: true });
  }

  return createOrder(db, customer, parsed, message, timestamp, res);
});

function createOrder(db, customer, data, message, timestamp, res) {
  const prod = data.product_id
    ? db.prepare('SELECT price FROM products WHERE id=?').get(data.product_id) : null;

  // orders + order_items en una sola transaccion -- si el proceso muriera
  // entre los dos inserts (antes eran dos statements sueltos) quedaria un
  // pedido huerfano sin items.
  const orderId = db.transaction(() => {
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
    const id = ins.lastInsertRowid;

    // Insertar items -- del multi-parser si vienen, o el item unico del pedido
    // simple (antes NO se guardaba nunca aca, asi que /analytics/products y
    // /analytics/summary -- que solo leen order_items -- ignoraban totalmente
    // los pedidos de un solo producto, que son la mayoria).
    const itemIns = db.prepare('INSERT INTO order_items (order_id,product_id,product_name,product_price,quantity) VALUES (?,?,?,?,?)');
    if (Array.isArray(data.items) && data.items.length) {
      for (const it of data.items) itemIns.run(id, it.product_id, it.product_name, it.product_price, it.quantity || 1);
    } else if (data.product_id) {
      itemIns.run(id, data.product_id, sanitize(data.product_name, 200), prod?.price ?? null, data.quantity || 1);
    }
    return id;
  })();

  const order = db.prepare('SELECT * FROM orders WHERE id=?').get(orderId);
  if (order.is_fiado) {
    db.prepare(`UPDATE messages SET flagged=1, flag_reason='fiado_pedido'
      WHERE phone=? AND direction='inbound' ORDER BY created_at DESC LIMIT 1`)
      .run(customer.phone);
  }
  queueBotReply(db, customer.phone, confirmationText(order));
  res.json({ success: true, order });
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
  const reply = `✅ *Pedido recibido:*\n${items.map(i => `📦 ${i.quantity}x ${i.product_name}`).join('\n')}\n📍 ${address}\n\nPronto confirmamos el envío.`;
  queueBotReply(db, customer.phone, reply);
  res.json({ success: true, order });
}

module.exports = router;
