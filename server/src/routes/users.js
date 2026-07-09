'use strict';
const express = require('express');
const router  = express.Router();
const bcrypt  = require('bcrypt');
const multer  = require('multer');
const fs      = require('fs');
const { getDB }     = require('../db/database');
const { adminAuth } = require('../middleware/auth');
const { sanitizeText } = require('../utils/sanitize');

const PICS_DIR = require('path').join(process.env.APPDATA || process.env.HOME, 'pedidos-bot', 'profile-pics');
fs.mkdirSync(PICS_DIR, { recursive: true });
const picUpload = multer({
  dest: PICS_DIR,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_, f, cb) => cb(null, f.mimetype.startsWith('image/')),
});

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
  ).run(name, credHash, credHash, display_name ? sanitizeText(display_name, 100) : name, role, address ? sanitizeText(address, 300) : null);

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

  if (req.body.display_name !== undefined) { updates.push('display_name=?'); vals.push(sanitizeText(req.body.display_name, 100)); }
  if (req.body.role !== undefined) {
    if (!['admin', 'worker', 'client'].includes(req.body.role))
      return res.status(400).json({ error: 'role debe ser admin, worker o client' });
    updates.push('role=?'); vals.push(req.body.role);
  }
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
  try {
    const r = db.prepare('DELETE FROM users WHERE id=?').run(id);
    if (!r.changes) return res.status(404).json({ error: 'Usuario no encontrado' });
    res.json({ ok: true });
  } catch (e) {
    // FK (orders.claimed_by, login_events.user_id, etc) impide borrar un
    // usuario con historial -- es el comportamiento correcto (preservar
    // trazabilidad de pedidos/sesiones), no un error real del servidor.
    // Antes esto caia al handler generico y devolvia 500.
    if (/FOREIGN KEY constraint failed/i.test(e.message)) {
      return res.status(409).json({ error: 'No se puede eliminar: el usuario tiene pedidos o sesiones registradas. Desactívalo en su lugar.' });
    }
    throw e;
  }
});

// GET /api/users/clients — list client users (admin only)
router.get('/clients', adminAuth, (req, res) => {
  const clients = getDB().prepare(
    `SELECT id, username, display_name, email, nickname, address, profile_pic, active, created_at
     FROM users WHERE role='client' ORDER BY created_at DESC`
  ).all();
  res.json({ clients });
});

// PUT /api/users/me — update own profile (any authenticated user)
router.put('/me', require('../middleware/auth').clientAuth, async (req, res) => {
  const db = getDB();
  const { display_name, address, nickname, bio, email } = req.body;
  const updates = [];
  const vals    = [];
  if (display_name !== undefined) { updates.push('display_name=?'); vals.push(sanitizeText(display_name, 100)); }
  if (address !== undefined)      { updates.push('address=?');      vals.push(sanitizeText(address, 300)); }
  if (nickname !== undefined)     { updates.push('nickname=?');     vals.push(sanitizeText(nickname, 50)); }
  if (bio !== undefined)          { updates.push('bio=?');          vals.push(sanitizeText(bio, 500)); }
  if (email !== undefined) {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email).trim()))
      return res.status(400).json({ error: 'Email inválido' });
    updates.push('email=?'); vals.push(String(email).trim().toLowerCase().slice(0,200));
  }
  if (!updates.length) return res.status(400).json({ error: 'Nada que actualizar' });
  vals.push(req.user.id);
  try {
    db.prepare(`UPDATE users SET ${updates.join(',')} WHERE id=?`).run(...vals);
  } catch (e) {
    if (String(e.message || '').includes('UNIQUE constraint failed')) {
      return res.status(409).json({ error: 'Ese correo ya está en uso por otra cuenta' });
    }
    throw e;
  }
  const user = db.prepare('SELECT id,username,display_name,role,email,address,nickname,bio,profile_pic FROM users WHERE id=?').get(req.user.id);
  res.json({ user });
});

// PUT /api/users/me/password — change own password
router.put('/me/password', require('../middleware/auth').clientAuth, async (req, res) => {
  const { current_password, new_password } = req.body;
  if (!current_password || !new_password)
    return res.status(400).json({ error: 'current_password y new_password requeridos' });
  if (String(new_password).length < 8)
    return res.status(400).json({ error: 'La nueva contraseña debe tener mínimo 8 caracteres' });
  const db   = getDB();
  const user = db.prepare('SELECT * FROM users WHERE id=?').get(req.user.id);
  const match = await bcrypt.compare(String(current_password), user.password_hash);
  if (!match) return res.status(401).json({ error: 'Contraseña actual incorrecta' });
  const hash = await bcrypt.hash(String(new_password), 10);
  db.prepare('UPDATE users SET password_hash=?, pin=? WHERE id=?').run(hash, hash, req.user.id);
  res.json({ ok: true });
});

// POST /api/users/me/profile-pic — upload profile photo
router.post('/me/profile-pic', require('../middleware/auth').clientAuth, picUpload.single('photo'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Imagen requerida' });
  const ext     = req.file.mimetype === 'image/png' ? 'png' : 'jpg';
  const newName = `${req.user.username}_${Date.now()}.${ext}`;
  const newPath = require('path').join(PICS_DIR, newName);
  try { fs.renameSync(req.file.path, newPath); } catch { fs.copyFileSync(req.file.path, newPath); fs.unlinkSync(req.file.path); }
  getDB().prepare('UPDATE users SET profile_pic=? WHERE id=?').run(newName, req.user.id);
  res.json({ filename: newName });
});

// GET /api/users/profile-pic/:filename — serve profile pic
router.get('/profile-pic/:filename', require('../middleware/auth').clientAuth, (req, res) => {
  const fp = require('path').join(PICS_DIR, require('path').basename(req.params.filename));
  if (!require('fs').existsSync(fp)) return res.status(404).end();
  res.sendFile(fp);
});

// DELETE /api/users/me/profile-pic — delete own profile pic
router.delete('/me/profile-pic', require('../middleware/auth').clientAuth, (req, res) => {
  const db   = getDB();
  const user = db.prepare('SELECT profile_pic FROM users WHERE id=?').get(req.user.id);
  if (user?.profile_pic) {
    try { fs.unlinkSync(require('path').join(PICS_DIR, user.profile_pic)); } catch {}
  }
  db.prepare('UPDATE users SET profile_pic=NULL WHERE id=?').run(req.user.id);
  res.json({ ok: true });
});

module.exports = router;
