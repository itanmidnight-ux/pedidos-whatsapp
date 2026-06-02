'use strict';
const express = require('express');
const router  = express.Router();
const bcrypt  = require('bcrypt');
const { getDB }     = require('../db/database');
const { adminAuth } = require('../middleware/auth');

const SALT = 10;
const SAFE_FIELDS = 'id, username, display_name, role, active, created_at';

// GET /api/users — list all (admin only)
router.get('/', adminAuth, (req, res) => {
  const users = getDB().prepare(`SELECT ${SAFE_FIELDS} FROM users ORDER BY id`).all();
  res.json({ users });
});

// POST /api/users — create user (admin only)
router.post('/', adminAuth, async (req, res) => {
  const { username, pin, display_name, role = 'worker' } = req.body;

  if (!username || typeof username !== 'string' || username.trim().length < 2)
    return res.status(400).json({ error: 'username requerido (mín 2 chars)' });
  if (!pin || String(pin).length < 4)
    return res.status(400).json({ error: 'pin requerido (mín 4 dígitos)' });
  if (!['admin', 'worker'].includes(role))
    return res.status(400).json({ error: 'role debe ser admin o worker' });

  const db   = getDB();
  const name = username.trim().toLowerCase();

  if (db.prepare('SELECT id FROM users WHERE username = ?').get(name))
    return res.status(409).json({ error: 'Usuario ya existe' });

  const [passHash, pinHash] = await Promise.all([
    bcrypt.hash(String(pin), SALT),
    bcrypt.hash(String(pin), SALT),
  ]);

  const result = db.prepare(
    'INSERT INTO users (username, password_hash, pin, display_name, role) VALUES (?,?,?,?,?)'
  ).run(name, passHash, pinHash, display_name?.trim() || name, role);

  const user = db.prepare(`SELECT ${SAFE_FIELDS} FROM users WHERE id = ?`).get(result.lastInsertRowid);
  res.status(201).json({ user });
});

// PUT /api/users/:id — update display_name, pin, role, active (admin only)
router.put('/:id', adminAuth, async (req, res) => {
  const db   = getDB();
  const id   = parseInt(req.params.id);
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
  if (!user) return res.status(404).json({ error: 'Usuario no encontrado' });

  // Admin cannot deactivate themselves
  if (req.user.id === id && req.body.active === 0)
    return res.status(400).json({ error: 'No puedes desactivar tu propio usuario' });

  const updates = [];
  const vals    = [];

  if (req.body.display_name !== undefined) { updates.push('display_name=?'); vals.push(req.body.display_name.trim()); }
  if (req.body.role         !== undefined) { updates.push('role=?');         vals.push(req.body.role); }
  if (req.body.active       !== undefined) { updates.push('active=?');       vals.push(req.body.active ? 1 : 0); }
  if (req.body.pin          !== undefined) {
    const [ph, pinh] = await Promise.all([bcrypt.hash(String(req.body.pin), SALT), bcrypt.hash(String(req.body.pin), SALT)]);
    updates.push('password_hash=?', 'pin=?');
    vals.push(ph, pinh);
  }

  if (!updates.length) return res.status(400).json({ error: 'Nada que actualizar' });

  vals.push(id);
  db.prepare(`UPDATE users SET ${updates.join(',')} WHERE id=?`).run(...vals);
  const updated = db.prepare(`SELECT ${SAFE_FIELDS} FROM users WHERE id=?`).get(id);
  res.json({ user: updated });
});

// DELETE /api/users/:id — soft delete (admin only, cannot delete self)
router.delete('/:id', adminAuth, (req, res) => {
  const id = parseInt(req.params.id);
  if (req.user.id === id) return res.status(400).json({ error: 'No puedes eliminarte a ti mismo' });
  const db = getDB();
  const r  = db.prepare('UPDATE users SET active=0 WHERE id=?').run(id);
  if (!r.changes) return res.status(404).json({ error: 'Usuario no encontrado' });
  res.json({ ok: true });
});

module.exports = router;
