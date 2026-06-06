'use strict';
const express = require('express');
const router  = express.Router();
const bcrypt  = require('bcrypt');
const { getDB }     = require('../db/database');
const { adminAuth } = require('../middleware/auth');

const SALT = 10;
const SAFE_FIELDS = 'id, username, display_name, role, active, address, created_at';

// GET /api/users — list all (admin only)
router.get('/', adminAuth, (req, res) => {
  const users = getDB().prepare(`SELECT ${SAFE_FIELDS} FROM users ORDER BY id`).all();
  res.json({ users });
});

// POST /api/users — create user (admin only)
router.post('/', adminAuth, async (req, res) => {
  const { username, pin, password, display_name, address, role = 'worker' } = req.body;
  const credential = password !== undefined ? String(password) : (pin !== undefined ? String(pin) : '');

  if (!username || typeof username !== 'string' || username.trim().length < 2)
    return res.status(400).json({ error: 'username requerido (mín 2 chars)' });
  if (!credential.length)
    return res.status(400).json({ error: 'contraseña requerida' });
  if (!['admin', 'worker', 'client'].includes(role))
    return res.status(400).json({ error: 'role debe ser admin, worker o client' });

  const db   = getDB();
  const name = username.trim().toLowerCase();

  if (db.prepare('SELECT id FROM users WHERE username = ?').get(name))
    return res.status(409).json({ error: 'Usuario ya existe' });

  const credHash = await bcrypt.hash(credential, SALT);

  const result = db.prepare(
    'INSERT INTO users (username, password_hash, pin, display_name, role, address) VALUES (?,?,?,?,?,?)'
  ).run(name, credHash, credHash, display_name?.trim() || name, role, address?.trim() || null);

  const user = db.prepare(`SELECT ${SAFE_FIELDS} FROM users WHERE id = ?`).get(result.lastInsertRowid);
  res.status(201).json({ user });
});

// PUT /api/users/:id — update display_name, password, role, active, address (admin only)
router.put('/:id', adminAuth, async (req, res) => {
  const db   = getDB();
  const id   = parseInt(req.params.id);
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
  if (!user) return res.status(404).json({ error: 'Usuario no encontrado' });

  if (req.user.id === id && req.body.active === 0)
    return res.status(400).json({ error: 'No puedes desactivar tu propio usuario' });

  const updates = [];
  const vals    = [];

  if (req.body.display_name !== undefined) { updates.push('display_name=?'); vals.push(req.body.display_name.trim()); }
  if (req.body.role         !== undefined) { updates.push('role=?');         vals.push(req.body.role); }
  if (req.body.active       !== undefined) { updates.push('active=?');       vals.push(req.body.active ? 1 : 0); }
  if (req.body.address      !== undefined) { updates.push('address=?');      vals.push(req.body.address?.trim() || null); }
  const newCredential = req.body.password !== undefined ? String(req.body.password)
                      : req.body.pin      !== undefined ? String(req.body.pin) : undefined;
  if (newCredential !== undefined) {
    const credHash = await bcrypt.hash(newCredential, SALT);
    updates.push('password_hash=?', 'pin=?');
    vals.push(credHash, credHash);
  }

  if (!updates.length) return res.status(400).json({ error: 'Nada que actualizar' });

  vals.push(id);
  db.prepare(`UPDATE users SET ${updates.join(',')} WHERE id=?`).run(...vals);
  const updated = db.prepare(`SELECT ${SAFE_FIELDS} FROM users WHERE id=?`).get(id);
  res.json({ user: updated });
});

// DELETE /api/users/:id — hard delete (admin only, cannot delete self)
router.delete('/:id', adminAuth, (req, res) => {
  const id = parseInt(req.params.id);
  if (req.user.id === id) return res.status(400).json({ error: 'No puedes eliminarte a ti mismo' });
  const db = getDB();
  const r  = db.prepare('DELETE FROM users WHERE id=?').run(id);
  if (!r.changes) return res.status(404).json({ error: 'Usuario no encontrado' });
  res.json({ ok: true });
});

module.exports = router;
