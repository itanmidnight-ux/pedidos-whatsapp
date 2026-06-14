'use strict';
const express = require('express');
const router  = express.Router();
const path    = require('path');
const fs      = require('fs');
const multer  = require('multer');
const { jwtAuth, apiKeyAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

// ── Media directory ───────────────────────────────────────────
const MEDIA_DIR = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot', 'media');
if (!fs.existsSync(MEDIA_DIR)) fs.mkdirSync(MEDIA_DIR, { recursive: true });

const DOCS_DIR = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot', 'docs');
if (!fs.existsSync(DOCS_DIR)) fs.mkdirSync(DOCS_DIR, { recursive: true });

const upload = multer({
  dest: MEDIA_DIR,
  limits: { fileSize: 64 * 1024 * 1024 },
  fileFilter: (_, file, cb) => {
    const ok = file.mimetype.startsWith('audio/')
      || file.mimetype.startsWith('image/')
      || file.mimetype.startsWith('video/')
      || file.mimetype === 'application/pdf'
      || file.mimetype === 'application/msword'
      || file.mimetype === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      || file.mimetype === 'application/octet-stream';
    cb(null, ok);
  },
});

function validPhone(p) { return /^\d{7,15}$/.test(String(p || '').trim()); }

// ── GET / — Conversaciones (no archivadas por defecto) ────────
router.get('/', jwtAuth, (req, res) => {
  const archived = req.query.archived === 'true' ? 1 : 0;
  const convs = getDB().prepare(`
    SELECT m.phone,
           COALESCE(c.name, m.customer_name) AS customer_name,
           c.profile_pic_url,
           COALESCE(c.archived, 0) AS archived,
      (SELECT content    FROM messages WHERE phone=m.phone ORDER BY created_at DESC LIMIT 1) AS last_msg,
      (SELECT created_at FROM messages WHERE phone=m.phone ORDER BY created_at DESC LIMIT 1) AS last_at,
      (SELECT media_type FROM messages WHERE phone=m.phone ORDER BY created_at DESC LIMIT 1) AS last_media_type,
      (SELECT COUNT(*)   FROM messages WHERE phone=m.phone AND direction='inbound' AND sent=0) AS unread,
      (SELECT COUNT(*)   FROM messages WHERE phone=m.phone AND flagged=1) AS flagged_count,
      (SELECT flag_reason FROM messages WHERE phone=m.phone AND flagged=1 ORDER BY created_at DESC LIMIT 1) AS flag_reason
    FROM messages m
    LEFT JOIN customers c ON c.phone = m.phone
    WHERE COALESCE(c.archived, 0) = ?
    GROUP BY m.phone
    ORDER BY flagged_count DESC, last_at DESC
  `).all(archived);
  res.json(convs);
});

// ── GET /flagged ──────────────────────────────────────────────
router.get('/flagged', jwtAuth, (req, res) => {
  res.json(getDB().prepare(
    `SELECT * FROM messages WHERE flagged=1 ORDER BY created_at DESC LIMIT 50`
  ).all());
});

// ── GET /outbound/pending — (bot) ─────────────────────────────
router.get('/outbound/pending', apiKeyAuth, (req, res) => {
  res.json({
    messages: getDB().prepare(
      `SELECT * FROM messages WHERE direction='outbound' AND sent=0 ORDER BY created_at ASC`
    ).all(),
  });
});

// ── GET /promotional ──────────────────────────────────────────
router.get('/promotional', jwtAuth, (req, res) => {
  res.json(getDB().prepare(
    `SELECT * FROM promotional_campaigns ORDER BY created_at DESC LIMIT 50`
  ).all());
});

// ── GET /media/:filename — Servir archivos de media y docs ───
router.get('/media/:filename', jwtAuth, (req, res) => {
  const filename  = path.basename(req.params.filename);
  const inMedia   = path.join(MEDIA_DIR, filename);
  const inDocs    = path.join(DOCS_DIR,  filename);
  const filepath  = fs.existsSync(inMedia) ? inMedia
                  : fs.existsSync(inDocs)  ? inDocs
                  : null;
  if (!filepath) return res.status(404).json({ error: 'Media no encontrada' });
  res.sendFile(filepath);
});

// ── DELETE /conversation/:phone — Borrar conversación ─────────
router.delete('/conversation/:phone', jwtAuth, (req, res) => {
  const phone = req.params.phone.trim();
  if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido' });
  const db = getDB();
  db.prepare('DELETE FROM messages WHERE phone=?').run(phone);
  db.prepare('DELETE FROM pending_orders WHERE phone=?').run(phone);
  res.json({ success: true });
});

// ── PUT /conversation/:phone/archive — Archivar/Desarchivar ───
router.put('/conversation/:phone/archive', jwtAuth, (req, res) => {
  const phone = req.params.phone.trim();
  if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido' });
  const { archived } = req.body;
  const db = getDB();
  db.prepare(`INSERT INTO customers (phone, archived) VALUES (?, ?)
    ON CONFLICT(phone) DO UPDATE SET archived = excluded.archived`)
    .run(phone, archived ? 1 : 0);
  res.json({ success: true });
});

// ── PUT /:phone/read — Marcar conversación como leída ─────────
router.put('/:phone/read', jwtAuth, (req, res) => {
  const phone = req.params.phone.trim();
  if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido' });
  getDB().prepare(
    `UPDATE messages SET sent=1 WHERE phone=? AND direction='inbound' AND sent=0`
  ).run(phone);
  res.json({ success: true });
});

// ── GET /:phone — Conversación individual ────────────────────
router.get('/:phone', jwtAuth, (req, res) => {
  if (!validPhone(req.params.phone)) return res.status(400).json({ error: 'phone inválido' });
  const msgs = getDB().prepare(
    `SELECT * FROM messages WHERE phone=? ORDER BY created_at ASC`
  ).all(req.params.phone.trim());
  res.json(msgs);
});

// ── PUT /:id/flag ─────────────────────────────────────────────
router.put('/:id/flag', jwtAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const { flagged, flag_reason } = req.body;
  const safeReason = flag_reason ? String(flag_reason).trim().slice(0, 200) : null;
  getDB().prepare('UPDATE messages SET flagged=?, flag_reason=? WHERE id=?')
    .run(flagged ? 1 : 0, safeReason, id);
  res.json({ success: true });
});

// ── POST /send-media — Enviar media al cliente ────────────────
router.post('/send-media', jwtAuth, upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Archivo requerido' });
  const { phone, media_type } = req.body;
  if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido' });
  const validTypes = ['audio', 'image', 'video', 'document'];
  if (!validTypes.includes(media_type)) return res.status(400).json({ error: 'media_type inválido' });

  const mimeExt = {
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif',
    'audio/mp4': 'm4a', 'audio/aac': 'aac', 'audio/ogg': 'ogg', 'audio/mpeg': 'mp3',
    'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm',
    'application/pdf': 'pdf',
  };
  const ext = mimeExt[req.file.mimetype]
    || (media_type === 'audio'    ? 'm4a'
      : media_type === 'video'    ? 'mp4'
      : media_type === 'document' ? 'bin'
      : 'jpg');
  const newFilename = `${phone.trim()}_${Date.now()}.${ext}`;
  const isDoc       = media_type === 'document';
  const destPath    = path.join(isDoc ? DOCS_DIR : MEDIA_DIR, newFilename);

  try {
    fs.renameSync(req.file.path, destPath);
  } catch {
    try { fs.copyFileSync(req.file.path, destPath); fs.unlinkSync(req.file.path); } catch (_) {}
  }

  const db = getDB();
  const customer = db.prepare('SELECT name FROM customers WHERE phone=?').get(phone.trim());
  const captions = { audio: '🎵 Audio', image: '📷 Imagen', video: '🎬 Video', document: '📄 Documento' };
  const caption  = captions[media_type] || media_type;
  const result   = db.prepare(
    `INSERT INTO messages (phone, customer_name, content, direction, sent, type, media_type, media_url)
     VALUES (?, ?, ?, 'outbound', 0, 'direct', ?, ?)`
  ).run(phone.trim(), customer?.name || null, caption, media_type, newFilename);

  res.json({ success: true, id: result.lastInsertRowid, filename: newFilename });
});

// ── POST /send — Enviar mensaje texto ────────────────────────
router.post('/send', jwtAuth, (req, res) => {
  const raw = String(req.body.phone || '').replace(/\D/g, '');
  // Normalize Colombian 10-digit mobiles to full E.164
  const phone = (raw.length === 10 && raw.startsWith('3')) ? '57' + raw : raw;
  if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido (7-15 dígitos)' });
  const { content } = req.body;
  if (!content || typeof content !== 'string' || content.trim().length === 0 || content.length > 1000) {
    return res.status(400).json({ error: 'content requerido (máximo 1000 caracteres)' });
  }
  const db       = getDB();
  const customer = db.prepare('SELECT name FROM customers WHERE phone=?').get(phone);
  const result   = db.prepare(
    `INSERT INTO messages (phone, customer_name, content, direction, sent, type)
     VALUES (?, ?, ?, 'outbound', 0, 'direct')`
  ).run(phone, customer?.name || null, content.trim());
  res.json({ success: true, id: result.lastInsertRowid });
});

// ── POST /promotional ─────────────────────────────────────────
router.post('/promotional', jwtAuth, (req, res) => {
  const { message, phones } = req.body;
  if (!message || typeof message !== 'string' || message.trim().length === 0 || message.length > 1000)
    return res.status(400).json({ error: 'message requerido (máximo 1000 caracteres)' });
  if (phones === undefined || phones === null)
    return res.status(400).json({ error: 'phones requerido: "all" o array de números' });

  const db = getDB();
  let targetPhones;
  if (phones === 'all') {
    targetPhones = db.prepare('SELECT DISTINCT phone FROM customers').all().map(r => r.phone);
    if (targetPhones.length === 0) return res.status(400).json({ error: 'No hay clientes registrados' });
  } else if (Array.isArray(phones) && phones.length > 0) {
    targetPhones = phones.map(p => String(p).replace(/\D/g, '')).filter(validPhone);
    if (targetPhones.length === 0) return res.status(400).json({ error: 'Ningún número válido' });
  } else {
    return res.status(400).json({ error: 'phones debe ser "all" o array' });
  }

  const msg  = message.trim();
  const stmt = db.prepare(
    `INSERT INTO messages (phone, content, direction, sent, type) VALUES (?, ?, 'outbound', 0, 'promotional')`
  );
  db.transaction(list => { for (const p of list) stmt.run(p, msg); })(targetPhones);

  const campaign = db.prepare(
    `INSERT INTO promotional_campaigns (message, target_type, sent_count) VALUES (?, ?, ?)`
  ).run(msg, phones === 'all' ? 'all' : 'custom', targetPhones.length);

  res.json({
    success: true, queued: targetPhones.length,
    campaign_id: campaign.lastInsertRowid,
    eta_minutes: Math.ceil(targetPhones.length * 3.5 / 60),
  });
});

// ── PUT /:id/sent — (bot) ─────────────────────────────────────
router.put('/:id/sent', apiKeyAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  getDB().prepare('UPDATE messages SET sent=1 WHERE id=?').run(id);
  res.json({ success: true });
});

module.exports = router;
