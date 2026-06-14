'use strict';
const express = require('express');
const router  = express.Router();
const path    = require('path');
const fs      = require('fs');
const multer  = require('multer');
const { adminAuth, clientAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

const ESTADOS_DIR = path.join(process.env.HOME || process.env.USERPROFILE, 'pedidos-bot', 'estados');
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

function enrichEstado(db, estado, username) {
  const heartCount   = db.prepare('SELECT COUNT(*) AS c FROM estado_reactions WHERE estado_id=?').get(estado.id)?.c ?? 0;
  const hasHearted   = !!db.prepare('SELECT 1 FROM estado_reactions WHERE estado_id=? AND username=?').get(estado.id, username);
  const commentCount = db.prepare('SELECT COUNT(*) AS c FROM estado_comments WHERE estado_id=?').get(estado.id)?.c ?? 0;
  return { ...estado, heart_count: heartCount, has_hearted: hasHearted, comment_count: commentCount };
}

// GET /api/estados — list active estados with reaction counts
router.get('/', clientAuth, (req, res) => {
  const db = getDB();
  const estados = db.prepare(`
    SELECT * FROM estados
    WHERE datetime('now','localtime') < expires_at
    ORDER BY created_at DESC
  `).all();
  res.json({ estados: estados.map(e => enrichEstado(db, e, req.user.username)) });
});

// POST /api/estados — create (admin only, 36h TTL)
router.post('/', adminAuth, upload.single('media'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No se recibió archivo de media' });
  const caption    = req.body.caption ? String(req.body.caption).trim().slice(0, 500) : null;
  const media_type = req.file.mimetype.startsWith('video') ? 'video' : 'image';
  const db = getDB();
  const result = db.prepare(`
    INSERT INTO estados (admin_username, filename, media_type, caption, expires_at)
    VALUES (?, ?, ?, ?, datetime('now','localtime','+36 hours'))
  `).run(req.user.username, req.file.filename, media_type, caption);
  const estado = db.prepare('SELECT * FROM estados WHERE id=?').get(result.lastInsertRowid);
  res.status(201).json({ estado: enrichEstado(db, estado, req.user.username) });
});

// DELETE /api/estados/:id — (admin only)
router.delete('/:id', adminAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const db = getDB();
  const estado = db.prepare('SELECT * FROM estados WHERE id=?').get(id);
  if (!estado) return res.status(404).json({ error: 'Estado no encontrado' });
  try { fs.unlinkSync(path.join(ESTADOS_DIR, estado.filename)); } catch {}
  db.prepare('DELETE FROM estados WHERE id=?').run(id);
  // Purge expired
  const expired = db.prepare(`SELECT * FROM estados WHERE datetime('now','localtime') >= expires_at`).all();
  expired.forEach(e => {
    try { fs.unlinkSync(path.join(ESTADOS_DIR, e.filename)); } catch {}
    db.prepare('DELETE FROM estados WHERE id=?').run(e.id);
  });
  res.json({ ok: true });
});

// POST /api/estados/:id/react — toggle heart
router.post('/:id/react', clientAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const db = getDB();
  const estado = db.prepare('SELECT id FROM estados WHERE id=?').get(id);
  if (!estado) return res.status(404).json({ error: 'Estado no encontrado' });
  const existing = db.prepare('SELECT id FROM estado_reactions WHERE estado_id=? AND username=?').get(id, req.user.username);
  if (existing) {
    db.prepare('DELETE FROM estado_reactions WHERE estado_id=? AND username=?').run(id, req.user.username);
  } else {
    db.prepare('INSERT OR IGNORE INTO estado_reactions (estado_id, username) VALUES (?,?)').run(id, req.user.username);
  }
  const heartCount = db.prepare('SELECT COUNT(*) AS c FROM estado_reactions WHERE estado_id=?').get(id)?.c ?? 0;
  res.json({ heart_count: heartCount, has_hearted: !existing });
});

// GET /api/estados/:id/comments
router.get('/:id/comments', clientAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const db = getDB();
  const comments = db.prepare(`
    SELECT id, username, display_name, comment, created_at
    FROM estado_comments WHERE estado_id=? ORDER BY created_at ASC
  `).all(id);
  res.json({ comments });
});

// POST /api/estados/:id/comments
router.post('/:id/comments', clientAuth, (req, res) => {
  const id      = parseInt(req.params.id, 10);
  const comment = String(req.body.comment || '').trim().slice(0, 500);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  if (!comment) return res.status(400).json({ error: 'Comentario vacío' });
  const db = getDB();
  const estado = db.prepare('SELECT id FROM estados WHERE id=?').get(id);
  if (!estado) return res.status(404).json({ error: 'Estado no encontrado' });
  const user = db.prepare('SELECT display_name FROM users WHERE username=?').get(req.user.username);
  const result = db.prepare(
    'INSERT INTO estado_comments (estado_id, username, display_name, comment) VALUES (?,?,?,?)'
  ).run(id, req.user.username, user?.display_name || req.user.username, comment);
  const created = db.prepare('SELECT * FROM estado_comments WHERE id=?').get(result.lastInsertRowid);
  res.status(201).json({ comment: created });
});

// Serve estado media (authenticated)
router.get('/media/:filename', clientAuth, (req, res) => {
  const fp = path.join(ESTADOS_DIR, path.basename(req.params.filename));
  if (!fs.existsSync(fp)) return res.status(404).json({ error: 'No encontrado' });
  res.sendFile(fp);
});

module.exports = router;
