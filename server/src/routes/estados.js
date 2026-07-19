'use strict';
const express = require('express');
const router  = express.Router();
const path    = require('path');
const fs      = require('fs');
const multer  = require('multer');
const { adminAuth, clientAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

const ESTADOS_DIR = path.join(process.env.APPDATA || process.env.HOME || process.env.USERPROFILE, 'pedidos-bot', 'estados');
fs.mkdirSync(ESTADOS_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, ESTADOS_DIR),
  filename:    (req, file, cb) => cb(null, `${Date.now()}-${file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_')}`),
});
const upload = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!file.mimetype.startsWith('image/') && !file.mimetype.startsWith('video/'))
      return cb(Object.assign(new Error('Solo imágenes o videos'), { status: 400 }));
    cb(null, true);
  },
});

async function enrichEstado(db, estado, username) {
  const { rows: heartRows } = await db.query('SELECT COUNT(*) AS c FROM estado_reactions WHERE estado_id=$1', [estado.id]);
  const { rows: hasHeartedRows } = await db.query('SELECT 1 FROM estado_reactions WHERE estado_id=$1 AND username=$2', [estado.id, username]);
  const { rows: commentRows } = await db.query('SELECT COUNT(*) AS c FROM estado_comments WHERE estado_id=$1', [estado.id]);
  return {
    ...estado,
    heart_count: Number(heartRows[0]?.c ?? 0),
    has_hearted: hasHeartedRows.length > 0,
    comment_count: Number(commentRows[0]?.c ?? 0),
  };
}

// GET /api/estados — list active estados with reaction counts
router.get('/', clientAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const { rows: estados } = await db.query(`
      SELECT * FROM estados
      WHERE now_iso() < expires_at
      ORDER BY created_at DESC
    `);
    const enriched = await Promise.all(estados.map(e => enrichEstado(db, e, req.user.username)));
    res.json({ estados: enriched });
  } catch (e) { next(e); }
});

// POST /api/estados — create (admin only, 36h TTL)
router.post('/', adminAuth, upload.single('media'), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No se recibió archivo de media' });
    const caption      = req.body.caption ? String(req.body.caption).trim().slice(0, 500) : null;
    const product_id   = req.body.product_id   ? parseInt(req.body.product_id, 10) || null : null;
    const product_name = req.body.product_name ? String(req.body.product_name).trim().slice(0, 200) : null;
    const media_type = req.file.mimetype.startsWith('video') ? 'video' : 'image';
    const db = getDB();
    const { rows } = await db.query(`
      INSERT INTO estados (admin_username, filename, media_type, caption, product_id, product_name, expires_at)
      VALUES ($1, $2, $3, $4, $5, $6, to_char((now() AT TIME ZONE 'UTC') + INTERVAL '36 hours', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
      RETURNING *
    `, [req.user.username, req.file.filename, media_type, caption, product_id, product_name]);
    const estado = rows[0];
    res.status(201).json({ estado: await enrichEstado(db, estado, req.user.username) });
  } catch (e) { next(e); }
});

// DELETE /api/estados/:id — (admin only)
router.delete('/:id', adminAuth, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
    const db = getDB();
    const { rows } = await db.query('SELECT * FROM estados WHERE id=$1', [id]);
    const estado = rows[0];
    if (!estado) return res.status(404).json({ error: 'Estado no encontrado' });
    try { fs.unlinkSync(path.join(ESTADOS_DIR, estado.filename)); } catch {}
    await db.query('DELETE FROM estados WHERE id=$1', [id]);
    // Purge expired
    const { rows: expired } = await db.query(`SELECT * FROM estados WHERE now_iso() >= expires_at`);
    for (const e of expired) {
      try { fs.unlinkSync(path.join(ESTADOS_DIR, e.filename)); } catch {}
      await db.query('DELETE FROM estados WHERE id=$1', [e.id]);
    }
    res.json({ ok: true });
  } catch (e) { next(e); }
});

// POST /api/estados/:id/react — toggle heart
router.post('/:id/react', clientAuth, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
    const db = getDB();
    const { rows: estadoRows } = await db.query('SELECT id FROM estados WHERE id=$1', [id]);
    if (!estadoRows[0]) return res.status(404).json({ error: 'Estado no encontrado' });
    const { rows: existingRows } = await db.query(
      'SELECT id FROM estado_reactions WHERE estado_id=$1 AND username=$2', [id, req.user.username]
    );
    const existing = existingRows[0];
    if (existing) {
      await db.query('DELETE FROM estado_reactions WHERE estado_id=$1 AND username=$2', [id, req.user.username]);
    } else {
      await db.query('INSERT INTO estado_reactions (estado_id, username) VALUES ($1,$2) ON CONFLICT DO NOTHING', [id, req.user.username]);
    }
    const { rows: countRows } = await db.query('SELECT COUNT(*) AS c FROM estado_reactions WHERE estado_id=$1', [id]);
    res.json({ heart_count: Number(countRows[0]?.c ?? 0), has_hearted: !existing });
  } catch (e) { next(e); }
});

// GET /api/estados/:id/comments
router.get('/:id/comments', clientAuth, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
    const { rows: comments } = await getDB().query(`
      SELECT id, username, display_name, comment, created_at
      FROM estado_comments WHERE estado_id=$1 ORDER BY created_at ASC
    `, [id]);
    res.json({ comments });
  } catch (e) { next(e); }
});

// POST /api/estados/:id/comments
router.post('/:id/comments', clientAuth, async (req, res, next) => {
  try {
    const id      = parseInt(req.params.id, 10);
    const comment = String(req.body.comment || '').trim().slice(0, 500);
    if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
    if (!comment) return res.status(400).json({ error: 'Comentario vacío' });
    const db = getDB();
    const { rows: estadoRows } = await db.query('SELECT id FROM estados WHERE id=$1', [id]);
    if (!estadoRows[0]) return res.status(404).json({ error: 'Estado no encontrado' });
    const { rows: userRows } = await db.query('SELECT display_name FROM users WHERE username=$1', [req.user.username]);
    const { rows } = await db.query(
      'INSERT INTO estado_comments (estado_id, username, display_name, comment) VALUES ($1,$2,$3,$4) RETURNING *',
      [id, req.user.username, userRows[0]?.display_name || req.user.username, comment]
    );
    res.status(201).json({ comment: rows[0] });
  } catch (e) { next(e); }
});

// GET /api/estados/:id/reactions — list of users who reacted (admin only)
router.get('/:id/reactions', adminAuth, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
    const { rows: reactions } = await getDB().query(`
      SELECT er.username, COALESCE(u.display_name, er.username) AS display_name, er.created_at
      FROM estado_reactions er
      LEFT JOIN users u ON u.username = er.username
      WHERE er.estado_id = $1
      ORDER BY er.created_at DESC
    `, [id]);
    res.json({ reactions });
  } catch (e) { next(e); }
});

// Serve estado media (authenticated)
router.get('/media/:filename', clientAuth, (req, res) => {
  const fp = path.join(ESTADOS_DIR, path.basename(req.params.filename));
  if (!fs.existsSync(fp)) return res.status(404).json({ error: 'No encontrado' });
  res.sendFile(fp);
});

module.exports = router;
