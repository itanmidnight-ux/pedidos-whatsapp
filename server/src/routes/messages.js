const express = require('express');
const router  = express.Router();
const { jwtAuth, apiKeyAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

function validPhone(p) { return /^\d{7,15}$/.test(String(p || '').trim()); }

// GET / — Conversaciones
router.get('/', jwtAuth, (req, res) => {
  const convs = getDB().prepare(`
    SELECT m.phone, m.customer_name,
      (SELECT content    FROM messages WHERE phone=m.phone ORDER BY created_at DESC LIMIT 1) as last_msg,
      (SELECT created_at FROM messages WHERE phone=m.phone ORDER BY created_at DESC LIMIT 1) as last_at,
      (SELECT COUNT(*)   FROM messages WHERE phone=m.phone AND direction='inbound' AND sent=0) as unread,
      (SELECT COUNT(*)   FROM messages WHERE phone=m.phone AND flagged=1) as flagged_count,
      (SELECT flag_reason FROM messages WHERE phone=m.phone AND flagged=1 ORDER BY created_at DESC LIMIT 1) as flag_reason
    FROM messages m
    GROUP BY m.phone
    ORDER BY flagged_count DESC, last_at DESC
  `).all();
  res.json(convs);
});

// GET /flagged — Mensajes marcados
router.get('/flagged', jwtAuth, (req, res) => {
  const rows = getDB().prepare(
    `SELECT * FROM messages WHERE flagged=1 ORDER BY created_at DESC LIMIT 50`
  ).all();
  res.json(rows);
});

// GET /outbound/pending — Mensajes pendientes de enviar (bot)
router.get('/outbound/pending', apiKeyAuth, (req, res) => {
  const pending = getDB().prepare(
    `SELECT * FROM messages WHERE direction='outbound' AND sent=0 ORDER BY created_at ASC`
  ).all();
  res.json(pending);
});

// GET /promotional — Historial de campañas promocionales
router.get('/promotional', jwtAuth, (req, res) => {
  const campaigns = getDB().prepare(
    `SELECT * FROM promotional_campaigns ORDER BY created_at DESC LIMIT 50`
  ).all();
  res.json(campaigns);
});

// GET /:phone — Conversación individual
router.get('/:phone', jwtAuth, (req, res) => {
  if (!validPhone(req.params.phone)) return res.status(400).json({ error: 'phone inválido' });
  const msgs = getDB().prepare(
    `SELECT * FROM messages WHERE phone=? ORDER BY created_at ASC`
  ).all(req.params.phone.trim());
  res.json(msgs);
});

// PUT /:id/flag — Marcar/desmarcar mensaje
router.put('/:id/flag', jwtAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const { flagged, flag_reason } = req.body;
  getDB().prepare('UPDATE messages SET flagged=?, flag_reason=? WHERE id=?')
    .run(flagged ? 1 : 0, flag_reason || null, id);
  res.json({ success: true });
});

// POST /send — Enviar mensaje directo a un número
router.post('/send', jwtAuth, (req, res) => {
  const { phone, content } = req.body;
  if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido (7-15 dígitos)' });
  if (!content || typeof content !== 'string' || content.trim().length === 0 || content.length > 1000) {
    return res.status(400).json({ error: 'content requerido (máximo 1000 caracteres)' });
  }
  const db       = getDB();
  const customer = db.prepare('SELECT name FROM customers WHERE phone=?').get(phone.trim());
  const result   = db.prepare(
    `INSERT INTO messages (phone, customer_name, content, direction, sent, type)
     VALUES (?, ?, ?, 'outbound', 0, 'direct')`
  ).run(phone.trim(), customer?.name || null, content.trim());
  res.json({ success: true, id: result.lastInsertRowid });
});

// POST /promotional — Enviar mensaje promocional masivo
router.post('/promotional', jwtAuth, (req, res) => {
  const { message, phones } = req.body;

  if (!message || typeof message !== 'string' || message.trim().length === 0 || message.length > 1000) {
    return res.status(400).json({ error: 'message requerido (máximo 1000 caracteres)' });
  }
  if (phones === undefined || phones === null) {
    return res.status(400).json({ error: 'phones requerido: "all" o array de números' });
  }

  const db = getDB();
  let targetPhones;

  if (phones === 'all') {
    targetPhones = db.prepare('SELECT DISTINCT phone FROM customers').all().map(r => r.phone);
    if (targetPhones.length === 0) {
      return res.status(400).json({ error: 'No hay clientes registrados aún' });
    }
  } else if (Array.isArray(phones) && phones.length > 0) {
    targetPhones = phones.map(p => String(p).replace(/\D/g, '')).filter(validPhone);
    if (targetPhones.length === 0) {
      return res.status(400).json({ error: 'Ningún número válido en phones' });
    }
  } else {
    return res.status(400).json({ error: 'phones debe ser "all" o array de números' });
  }

  const msg  = message.trim();
  const stmt = db.prepare(
    `INSERT INTO messages (phone, content, direction, sent, type) VALUES (?, ?, 'outbound', 0, 'promotional')`
  );
  const insertAll = db.transaction(list => {
    for (const phone of list) stmt.run(phone, msg);
  });
  insertAll(targetPhones);

  const campaign = db.prepare(
    `INSERT INTO promotional_campaigns (message, target_type, sent_count)
     VALUES (?, ?, ?)`
  ).run(msg, phones === 'all' ? 'all' : 'custom', targetPhones.length);

  const estimatedMinutes = Math.ceil(targetPhones.length * 3.5 / 60);
  res.json({
    success:     true,
    queued:      targetPhones.length,
    campaign_id: campaign.lastInsertRowid,
    eta_minutes: estimatedMinutes,
  });
});

// PUT /:id/sent — Marcar mensaje como enviado (bot)
router.put('/:id/sent', apiKeyAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  getDB().prepare('UPDATE messages SET sent=1 WHERE id=?').run(id);
  res.json({ success: true });
});

module.exports = router;
