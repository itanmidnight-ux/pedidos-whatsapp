'use strict';
const express = require('express');
const router  = express.Router();
const { adminAuth, clientAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

// GET /api/settings — get all settings (admin) or public subset (client)
router.get('/', clientAuth, (req, res) => {
  const db = getDB();
  if (req.user.role === 'admin') {
    const rows = db.prepare('SELECT key, value FROM settings').all();
    const settings = {};
    rows.forEach(r => { settings[r.key] = r.value; });
    return res.json({ settings });
  }
  // Clients only get nequi_phone + nequi_name + empresa_nombre + horario_atencion
  const allowed = ['nequi_phone', 'nequi_name', 'empresa_nombre', 'horario_atencion'];
  const settings = {};
  allowed.forEach(k => {
    const row = db.prepare('SELECT value FROM settings WHERE key=?').get(k);
    if (row) settings[k] = row.value;
  });
  res.json({ settings });
});

const ALLOWED_SETTINGS_KEYS = [
  'nequi_phone', 'nequi_name',
  'empresa_nombre', 'empresa_descripcion', 'horario_atencion',
  'theme_primary', 'theme_accent', 'theme_name',
];

// PUT /api/settings — update setting (admin only)
router.put('/', adminAuth, (req, res) => {
  const { key, value } = req.body;
  if (!key || value === undefined) return res.status(400).json({ error: 'key y value requeridos' });
  if (!ALLOWED_SETTINGS_KEYS.includes(key))
    return res.status(400).json({ error: `key inválido. Permitidos: ${ALLOWED_SETTINGS_KEYS.join(', ')}` });
  const strVal = String(value).trim();
  if (strVal.length > 500) return res.status(400).json({ error: 'value máximo 500 caracteres' });
  getDB().prepare(`
    INSERT INTO settings (key, value, updated_at) VALUES (?, ?, datetime('now','localtime'))
    ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at
  `).run(key, strVal);
  res.json({ ok: true });
});

const multer = require('multer');
const path   = require('path');
const fs     = require('fs');

const LOGO_DIR = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot', 'branding');
if (!fs.existsSync(LOGO_DIR)) fs.mkdirSync(LOGO_DIR, { recursive: true });

const logoUpload = multer({
  dest: LOGO_DIR,
  limits: { fileSize: 4 * 1024 * 1024 },
  fileFilter: (_, file, cb) => cb(null, file.mimetype.startsWith('image/')),
});

// POST /api/settings/logo — subir logo de marca (admin only)
router.post('/logo', adminAuth, logoUpload.single('logo'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Archivo requerido' });
  const ext = req.file.mimetype === 'image/png' ? 'png' : 'jpg';
  const filename = `logo_${Date.now()}.${ext}`;
  fs.renameSync(req.file.path, path.join(LOGO_DIR, filename));
  getDB().prepare(`INSERT INTO settings (key, value) VALUES ('theme_logo_url', ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value`).run(filename);
  res.json({ filename });
});

// GET /api/settings/logo/:filename — servir el logo (publico, no es dato sensible)
router.get('/logo/:filename', (req, res) => {
  const filepath = path.join(LOGO_DIR, path.basename(req.params.filename));
  if (!fs.existsSync(filepath)) return res.status(404).json({ error: 'Logo no encontrado' });
  res.sendFile(filepath);
});

module.exports = router;
