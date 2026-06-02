const express = require('express');
const router = express.Router();
const { jwtAuth, apiKeyAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

function validPhone(p) { return /^\d{7,15}$/.test(String(p || '').trim()); }

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

router.get('/flagged', jwtAuth, (req, res) => {
  const rows = getDB().prepare(`
    SELECT * FROM messages WHERE flagged=1 ORDER BY created_at DESC LIMIT 50
  `).all();
  res.json(rows);
});

router.put('/:id/flag', jwtAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const { flagged, flag_reason } = req.body;
  getDB().prepare('UPDATE messages SET flagged=?, flag_reason=? WHERE id=?')
    .run(flagged ? 1 : 0, flag_reason || null, id);
  res.json({ success: true });
});

router.get('/outbound/pending', apiKeyAuth, (req, res) => {
  const pending = getDB().prepare(
    `SELECT * FROM messages WHERE direction='outbound' AND sent=0 ORDER BY created_at ASC`
  ).all();
  res.json(pending);
});

router.get('/:phone', jwtAuth, (req, res) => {
  if (!validPhone(req.params.phone)) return res.status(400).json({ error: 'phone inválido' });
  const msgs = getDB().prepare(`SELECT * FROM messages WHERE phone=? ORDER BY created_at ASC`).all(req.params.phone.trim());
  res.json(msgs);
});

router.post('/send', jwtAuth, (req, res) => {
  const { phone, content } = req.body;
  if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido (7-15 dígitos)' });
  if (!content || typeof content !== 'string' || content.trim().length === 0 || content.length > 1000) {
    return res.status(400).json({ error: 'content requerido (máximo 1000 caracteres)' });
  }
  const db = getDB();
  const customer = db.prepare('SELECT name FROM customers WHERE phone=?').get(phone.trim());
  const result = db.prepare(`
    INSERT INTO messages (phone, customer_name, content, direction, sent)
    VALUES (?, ?, ?, 'outbound', 0)
  `).run(phone.trim(), customer?.name || null, content.trim());
  res.json({ success: true, id: result.lastInsertRowid });
});

router.put('/:id/sent', apiKeyAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  getDB().prepare('UPDATE messages SET sent=1 WHERE id=?').run(id);
  res.json({ success: true });
});

module.exports = router;
