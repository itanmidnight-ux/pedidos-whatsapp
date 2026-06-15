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
  'nequi_phone', 'nequi_name', 'business_name', 'business_phone',
  'delivery_message', 'greeting_message',
  'empresa_nombre', 'empresa_descripcion', 'horario_atencion',
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

module.exports = router;
