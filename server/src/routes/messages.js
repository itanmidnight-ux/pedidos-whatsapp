'use strict';
const express = require('express');
const router  = express.Router();
const path    = require('path');
const fs      = require('fs');
const multer  = require('multer');
const { staffAuth, adminAuth, apiKeyAuth } = require('../middleware/auth');
const { getDB, withTransaction } = require('../db/database');
const { sanitizeText } = require('../utils/sanitize');

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
router.get('/', staffAuth, async (req, res, next) => {
  try {
    const archived = req.query.archived === 'true' ? 1 : 0;
    // MAX(...) envuelve columnas no agregadas -- Postgres exige que todo lo
    // no listado en GROUP BY sea agregado (SQLite era laxo con esto). Los
    // subqueries correlacionados ya devuelven un solo valor por m.phone, asi
    // que MAX() es un no-op semantico aca (mismo valor en todo el grupo).
    const { rows: convs } = await getDB().query(`
      SELECT m.phone,
             MAX(COALESCE(c.name, m.customer_name)) AS customer_name,
             MAX(c.profile_pic_url) AS profile_pic_url,
             MAX(COALESCE(c.archived, 0)) AS archived,
        MAX((SELECT content    FROM messages WHERE phone=m.phone AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1)) AS last_msg,
        MAX((SELECT created_at FROM messages WHERE phone=m.phone AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1)) AS last_at,
        MAX((SELECT media_type FROM messages WHERE phone=m.phone AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1)) AS last_media_type,
        MAX((SELECT COUNT(*)   FROM messages WHERE phone=m.phone AND direction='inbound' AND sent=0 AND deleted_at IS NULL)) AS unread,
        MAX((SELECT COUNT(*)   FROM messages WHERE phone=m.phone AND flagged=1 AND deleted_at IS NULL)) AS flagged_count,
        MAX((SELECT flag_reason FROM messages WHERE phone=m.phone AND flagged=1 AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1)) AS flag_reason
      FROM messages m
      LEFT JOIN customers c ON c.phone = m.phone
      WHERE COALESCE(c.archived, 0) = $1 AND m.deleted_at IS NULL
      GROUP BY m.phone
      ORDER BY flagged_count DESC, last_at DESC
    `, [archived]);
    res.json(convs.map(c => ({ ...c, unread: Number(c.unread), flagged_count: Number(c.flagged_count) })));
  } catch (e) { next(e); }
});

// ── GET /flagged ──────────────────────────────────────────────
router.get('/flagged', staffAuth, async (req, res, next) => {
  try {
    const { rows } = await getDB().query(
      `SELECT * FROM messages WHERE flagged=1 AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 50`
    );
    res.json(rows);
  } catch (e) { next(e); }
});

// ── GET /outbound/pending — (bot) ─────────────────────────────
router.get('/outbound/pending', apiKeyAuth, async (req, res, next) => {
  try {
    const { rows } = await getDB().query(`
      SELECT m.*, c.wa_jid AS wa_jid
      FROM messages m
      LEFT JOIN customers c ON c.phone = m.phone
      WHERE m.direction='outbound' AND m.sent=0
      ORDER BY m.created_at ASC
    `);
    res.json({ messages: rows });
  } catch (e) { next(e); }
});

// ── GET /promotional ──────────────────────────────────────────
router.get('/promotional', staffAuth, async (req, res, next) => {
  try {
    const { rows } = await getDB().query(
      `SELECT * FROM promotional_campaigns ORDER BY created_at DESC LIMIT 50`
    );
    res.json(rows);
  } catch (e) { next(e); }
});

// ── GET /media/:filename — Servir archivos de media y docs ───
router.get('/media/:filename', staffAuth, (req, res) => {
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
// Soft-delete: desaparece de la app pero el texto queda en la base para
// siempre, para poder exportarlo despues (pestaña Datos > exportar PDF).
router.delete('/conversation/:phone', staffAuth, async (req, res, next) => {
  try {
    const phone = req.params.phone.trim();
    if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido' });
    const db = getDB();
    await db.query(`UPDATE messages SET deleted_at=now_iso() WHERE phone=$1 AND deleted_at IS NULL`, [phone]);
    await db.query('DELETE FROM pending_orders WHERE phone=$1', [phone]);
    res.json({ success: true });
  } catch (e) { next(e); }
});

// ── PUT /conversation/:phone/archive — Archivar/Desarchivar ───
router.put('/conversation/:phone/archive', staffAuth, async (req, res, next) => {
  try {
    const phone = req.params.phone.trim();
    if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido' });
    const { archived } = req.body;
    await getDB().query(`INSERT INTO customers (phone, archived) VALUES ($1, $2)
      ON CONFLICT(phone) DO UPDATE SET archived = excluded.archived`, [phone, archived ? 1 : 0]);
    res.json({ success: true });
  } catch (e) { next(e); }
});

// ── PUT /:phone/read — Marcar conversación como leída ─────────
router.put('/:phone/read', staffAuth, async (req, res, next) => {
  try {
    const phone = req.params.phone.trim();
    if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido' });
    await getDB().query(
      `UPDATE messages SET sent=1 WHERE phone=$1 AND direction='inbound' AND sent=0`, [phone]
    );
    res.json({ success: true });
  } catch (e) { next(e); }
});

// ── GET /:phone — Conversación individual ────────────────────
router.get('/:phone', staffAuth, async (req, res, next) => {
  try {
    if (!validPhone(req.params.phone)) return res.status(400).json({ error: 'phone inválido' });
    const { rows } = await getDB().query(
      `SELECT * FROM messages WHERE phone=$1 AND deleted_at IS NULL ORDER BY created_at ASC`,
      [req.params.phone.trim()]
    );
    res.json(rows);
  } catch (e) { next(e); }
});

// ── PUT /:id/flag ─────────────────────────────────────────────
router.put('/:id/flag', staffAuth, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
    const { flagged, flag_reason } = req.body;
    const safeReason = flag_reason ? String(flag_reason).trim().slice(0, 200) : null;
    await getDB().query('UPDATE messages SET flagged=$1, flag_reason=$2 WHERE id=$3',
      [flagged ? 1 : 0, safeReason, id]);
    res.json({ success: true });
  } catch (e) { next(e); }
});

// ── POST /send-media — Enviar media al cliente ────────────────
router.post('/send-media', staffAuth, upload.single('file'), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'Archivo requerido' });

    const { fileTypeFromFile } = await import('file-type');
    const detected = await fileTypeFromFile(req.file.path).catch(() => null);
    const allowedRealTypes = /^(audio|image|video)\//.test(detected?.mime || '')
      || detected?.mime === 'application/pdf';
    // Si file-type no reconoce ningun magic number conocido (documentos Word
    // .doc/.docx son ZIP/OLE sin firma unica reconocible por esta lib para
    // todos los casos) Y el cliente declaro octet-stream, es la combinacion
    // exacta que describe el hallazgo -- rechazar. mimetype declarado
    // confiable (no octet-stream) para Word se deja pasar como hoy.
    const declaredOctetStream = req.file.mimetype === 'application/octet-stream';
    if (declaredOctetStream && (!detected || !allowedRealTypes)) {
      fs.unlink(req.file.path, () => {});
      return res.status(400).json({ error: 'Tipo de archivo no reconocido o no permitido' });
    }
    if (detected && !allowedRealTypes && !['application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'].includes(req.file.mimetype)) {
      fs.unlink(req.file.path, () => {});
      return res.status(400).json({ error: 'El contenido real del archivo no coincide con un tipo permitido' });
    }

    const { phone, media_type } = req.body;
    if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido' });
    const validTypes = ['audio', 'image', 'video', 'document'];
    if (!validTypes.includes(media_type)) return res.status(400).json({ error: 'media_type inválido' });

    const mimeExt = {
      'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif',
      'audio/mp4': 'm4a', 'audio/aac': 'aac', 'audio/ogg': 'ogg', 'audio/mpeg': 'mp3',
      'audio/webm': 'weba', // audio grabado desde navegador (Chrome/Firefox no soportan aac/m4a)
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
    const { rows: custRows } = await db.query('SELECT name FROM customers WHERE phone=$1', [phone.trim()]);
    const captions = { audio: '🎵 Audio', image: '📷 Imagen', video: '🎬 Video', document: '📄 Documento' };
    const caption  = captions[media_type] || media_type;
    const { rows } = await db.query(
      `INSERT INTO messages (phone, customer_name, content, direction, sent, type, media_type, media_url)
       VALUES ($1, $2, $3, 'outbound', 0, 'direct', $4, $5) RETURNING id`,
      [phone.trim(), custRows[0]?.name || null, caption, media_type, newFilename]
    );

    res.json({ success: true, id: rows[0].id, filename: newFilename });
  } catch (e) { next(e); }
});

// ── POST /send — Enviar mensaje texto ────────────────────────
router.post('/send', staffAuth, async (req, res, next) => {
  try {
    const raw = String(req.body.phone || '').replace(/\D/g, '');
    // Normalize Colombian 10-digit mobiles to full E.164
    const phone = (raw.length === 10 && raw.startsWith('3')) ? '57' + raw : raw;
    if (!validPhone(phone)) return res.status(400).json({ error: 'phone inválido (7-15 dígitos)' });
    const { content } = req.body;
    if (!content || typeof content !== 'string' || content.trim().length === 0 || content.length > 1000) {
      return res.status(400).json({ error: 'content requerido (máximo 1000 caracteres)' });
    }
    const db       = getDB();
    const { rows: custRows } = await db.query('SELECT name FROM customers WHERE phone=$1', [phone]);
    const { rows } = await db.query(
      `INSERT INTO messages (phone, customer_name, content, direction, sent, type)
       VALUES ($1, $2, $3, 'outbound', 0, 'direct') RETURNING id`,
      [phone, custRows[0]?.name || null, sanitizeText(content.trim(), 1000)]
    );
    res.json({ success: true, id: rows[0].id });
  } catch (e) { next(e); }
});

// ── POST /promotional ─────────────────────────────────────────
router.post('/promotional', adminAuth, async (req, res, next) => {
  try {
    const { message, phones } = req.body;
    if (!message || typeof message !== 'string' || message.trim().length === 0 || message.length > 1000)
      return res.status(400).json({ error: 'message requerido (máximo 1000 caracteres)' });
    if (phones === undefined || phones === null)
      return res.status(400).json({ error: 'phones requerido: "all" o array de números' });

    const db = getDB();
    let targetPhones;
    if (phones === 'all') {
      const { rows } = await db.query('SELECT DISTINCT phone FROM customers');
      targetPhones = rows.map(r => r.phone);
      if (targetPhones.length === 0) return res.status(400).json({ error: 'No hay clientes registrados' });
    } else if (Array.isArray(phones) && phones.length > 0) {
      targetPhones = phones.map(p => String(p).replace(/\D/g, '')).filter(validPhone);
      if (targetPhones.length === 0) return res.status(400).json({ error: 'Ningún número válido' });
    } else {
      return res.status(400).json({ error: 'phones debe ser "all" o array' });
    }

    const msg = sanitizeText(message.trim(), 1000);
    await withTransaction(async (client) => {
      for (const p of targetPhones) {
        await client.query(
          `INSERT INTO messages (phone, content, direction, sent, type) VALUES ($1, $2, 'outbound', 0, 'promotional')`,
          [p, msg]
        );
      }
    });

    const { rows: campaignRows } = await db.query(
      `INSERT INTO promotional_campaigns (message, target_type, sent_count) VALUES ($1, $2, $3) RETURNING id`,
      [msg, phones === 'all' ? 'all' : 'custom', targetPhones.length]
    );

    res.json({
      success: true, queued: targetPhones.length,
      campaign_id: campaignRows[0].id,
      eta_minutes: Math.ceil(targetPhones.length * 3.5 / 60),
    });
  } catch (e) { next(e); }
});

// ── PUT /:id/sent — (bot) ─────────────────────────────────────
router.put('/:id/sent', apiKeyAuth, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
    await getDB().query('UPDATE messages SET sent=1 WHERE id=$1', [id]);
    res.json({ success: true });
  } catch (e) { next(e); }
});

module.exports = router;
