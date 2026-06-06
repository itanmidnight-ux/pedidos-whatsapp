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
      return cb(Object.assign(new Error('Solo imágenes o videos (jpg, png, webp, gif, mp4, mov, webm)'), { status: 400 }));
    cb(null, true);
  },
});

// GET /api/estados — list active estados (not expired)
router.get('/', clientAuth, (req, res) => {
  const estados = getDB().prepare(`
    SELECT * FROM estados
    WHERE datetime('now','localtime') < expires_at
    ORDER BY created_at DESC
  `).all();
  res.json({ estados });
});

// POST /api/estados — create estado (admin only, 32h TTL)
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
  res.status(201).json({ estado });
});

// DELETE /api/estados/:id — delete estado (admin only)
router.delete('/:id', adminAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const db = getDB();
  const estado = db.prepare('SELECT * FROM estados WHERE id=?').get(id);
  if (!estado) return res.status(404).json({ error: 'Estado no encontrado' });
  try { fs.unlinkSync(path.join(ESTADOS_DIR, estado.filename)); } catch {}
  db.prepare('DELETE FROM estados WHERE id=?').run(id);
  // Also purge expired ones opportunistically
  const expired = db.prepare(`SELECT * FROM estados WHERE datetime('now','localtime') >= expires_at`).all();
  expired.forEach(e => {
    try { fs.unlinkSync(path.join(ESTADOS_DIR, e.filename)); } catch {}
    db.prepare('DELETE FROM estados WHERE id=?').run(e.id);
  });
  res.json({ ok: true });
});

// Serve estado media (authenticated)
router.get('/media/:filename', clientAuth, (req, res) => {
  const fp = path.join(ESTADOS_DIR, path.basename(req.params.filename));
  if (!fs.existsSync(fp)) return res.status(404).json({ error: 'No encontrado' });
  res.sendFile(fp);
});

module.exports = router;
