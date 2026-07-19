'use strict';
const express = require('express');
const router  = express.Router();
const bcrypt  = require('bcrypt');
const multer  = require('multer');
const fs      = require('fs');
const path    = require('path');
const { getDB }     = require('../db/database');
const { adminAuth, clientAuth } = require('../middleware/auth');
const { sanitizeText } = require('../utils/sanitize');

const PICS_DIR = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot', 'profile-pics');
fs.mkdirSync(PICS_DIR, { recursive: true });
const picUpload = multer({
  dest: PICS_DIR,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_, f, cb) => cb(null, f.mimetype.startsWith('image/')),
});

const SALT = 10;
const SAFE_FIELDS = 'id, username, display_name, role, active, address, created_at';

// GET /api/users — list all (admin only)
router.get('/', adminAuth, async (req, res, next) => {
  try {
    const { rows: users } = await getDB().query(`SELECT ${SAFE_FIELDS} FROM users ORDER BY id`);
    res.json({ users });
  } catch (e) { next(e); }
});

// POST /api/users — create user (admin only)
router.post('/', adminAuth, async (req, res, next) => {
  try {
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

    const { rows: existing } = await db.query('SELECT id FROM users WHERE username = $1', [name]);
    if (existing[0]) return res.status(409).json({ error: 'Usuario ya existe' });

    const credHash = await bcrypt.hash(credential, SALT);

    const { rows } = await db.query(
      'INSERT INTO users (username, password_hash, pin, display_name, role, address) VALUES ($1,$2,$3,$4,$5,$6) RETURNING id',
      [name, credHash, credHash, display_name ? sanitizeText(display_name, 100) : name, role, address ? sanitizeText(address, 300) : null]
    );

    const { rows: userRows } = await db.query(`SELECT ${SAFE_FIELDS} FROM users WHERE id = $1`, [rows[0].id]);
    res.status(201).json({ user: userRows[0] });
  } catch (e) { next(e); }
});

// PUT /api/users/:id — update display_name, password, role, active, address (admin only)
router.put('/:id', adminAuth, async (req, res, next) => {
  try {
    const db   = getDB();
    const id   = parseInt(req.params.id, 10);
    const { rows: userRows } = await db.query('SELECT * FROM users WHERE id = $1', [id]);
    const user = userRows[0];
    if (!user) return res.status(404).json({ error: 'Usuario no encontrado' });

    if (req.user.id === id && req.body.active === 0)
      return res.status(400).json({ error: 'No puedes desactivar tu propio usuario' });

    const updates = [];
    const vals    = [];

    if (req.body.display_name !== undefined) { vals.push(sanitizeText(req.body.display_name, 100)); updates.push(`display_name=$${vals.length}`); }
    if (req.body.role !== undefined) {
      if (!['admin', 'worker', 'client'].includes(req.body.role))
        return res.status(400).json({ error: 'role debe ser admin, worker o client' });
      vals.push(req.body.role); updates.push(`role=$${vals.length}`);
    }
    if (req.body.active       !== undefined) { vals.push(req.body.active ? 1 : 0); updates.push(`active=$${vals.length}`); }
    if (req.body.address      !== undefined) { vals.push(req.body.address?.trim() || null); updates.push(`address=$${vals.length}`); }
    const newCredential = req.body.password !== undefined ? String(req.body.password)
                        : req.body.pin      !== undefined ? String(req.body.pin) : undefined;
    if (newCredential !== undefined) {
      const credHash = await bcrypt.hash(newCredential, SALT);
      vals.push(credHash); updates.push(`password_hash=$${vals.length}`);
      vals.push(credHash); updates.push(`pin=$${vals.length}`);
    }

    if (!updates.length) return res.status(400).json({ error: 'Nada que actualizar' });

    vals.push(id);
    await db.query(`UPDATE users SET ${updates.join(',')} WHERE id=$${vals.length}`, vals);
    const { rows: updatedRows } = await db.query(`SELECT ${SAFE_FIELDS} FROM users WHERE id=$1`, [id]);
    res.json({ user: updatedRows[0] });
  } catch (e) { next(e); }
});

// DELETE /api/users/:id — hard delete (admin only, cannot delete self)
router.delete('/:id', adminAuth, async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (req.user.id === id) return res.status(400).json({ error: 'No puedes eliminarte a ti mismo' });
    const db = getDB();
    try {
      const result = await db.query('DELETE FROM users WHERE id=$1', [id]);
      if (!result.rowCount) return res.status(404).json({ error: 'Usuario no encontrado' });
      res.json({ ok: true });
    } catch (e) {
      // FK (orders.claimed_by, login_events.user_id, etc) impide borrar un
      // usuario con historial -- es el comportamiento correcto (preservar
      // trazabilidad de pedidos/sesiones), no un error real del servidor.
      // codigo 23503 = foreign_key_violation (estandar SQLSTATE de Postgres).
      if (e.code === '23503') {
        return res.status(409).json({ error: 'No se puede eliminar: el usuario tiene pedidos o sesiones registradas. Desactívalo en su lugar.' });
      }
      throw e;
    }
  } catch (e) { next(e); }
});

// GET /api/users/clients — list client users (admin only)
router.get('/clients', adminAuth, async (req, res, next) => {
  try {
    const { rows: clients } = await getDB().query(
      `SELECT id, username, display_name, email, nickname, address, profile_pic, active, created_at
       FROM users WHERE role='client' ORDER BY created_at DESC`
    );
    res.json({ clients });
  } catch (e) { next(e); }
});

// PUT /api/users/me — update own profile (any authenticated user)
router.put('/me', clientAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const { display_name, address, nickname, bio, email } = req.body;
    const updates = [];
    const vals    = [];
    if (display_name !== undefined) { vals.push(sanitizeText(display_name, 100)); updates.push(`display_name=$${vals.length}`); }
    if (address !== undefined)      { vals.push(sanitizeText(address, 300));      updates.push(`address=$${vals.length}`); }
    if (nickname !== undefined)     { vals.push(sanitizeText(nickname, 50));      updates.push(`nickname=$${vals.length}`); }
    if (bio !== undefined)          { vals.push(sanitizeText(bio, 500));          updates.push(`bio=$${vals.length}`); }
    if (email !== undefined) {
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email).trim()))
        return res.status(400).json({ error: 'Email inválido' });
      vals.push(String(email).trim().toLowerCase().slice(0,200)); updates.push(`email=$${vals.length}`);
    }
    if (!updates.length) return res.status(400).json({ error: 'Nada que actualizar' });
    vals.push(req.user.id);
    try {
      await db.query(`UPDATE users SET ${updates.join(',')} WHERE id=$${vals.length}`, vals);
    } catch (e) {
      if (e.code === '23505') { // unique_violation
        return res.status(409).json({ error: 'Ese correo ya está en uso por otra cuenta' });
      }
      throw e;
    }
    const { rows } = await db.query('SELECT id,username,display_name,role,email,address,nickname,bio,profile_pic FROM users WHERE id=$1', [req.user.id]);
    res.json({ user: rows[0] });
  } catch (e) { next(e); }
});

// PUT /api/users/me/password — change own password
router.put('/me/password', clientAuth, async (req, res, next) => {
  try {
    const { current_password, new_password } = req.body;
    if (!current_password || !new_password)
      return res.status(400).json({ error: 'current_password y new_password requeridos' });
    if (String(new_password).length < 8)
      return res.status(400).json({ error: 'La nueva contraseña debe tener mínimo 8 caracteres' });
    const db   = getDB();
    const { rows } = await db.query('SELECT * FROM users WHERE id=$1', [req.user.id]);
    const user = rows[0];
    const match = await bcrypt.compare(String(current_password), user.password_hash);
    if (!match) return res.status(401).json({ error: 'Contraseña actual incorrecta' });
    const hash = await bcrypt.hash(String(new_password), 10);
    await db.query('UPDATE users SET password_hash=$1, pin=$2 WHERE id=$3', [hash, hash, req.user.id]);
    res.json({ ok: true });
  } catch (e) { next(e); }
});

// POST /api/users/me/profile-pic — upload profile photo
router.post('/me/profile-pic', clientAuth, picUpload.single('photo'), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'Imagen requerida' });
    const ext     = req.file.mimetype === 'image/png' ? 'png' : 'jpg';
    const newName = `${req.user.username}_${Date.now()}.${ext}`;
    const newPath = path.join(PICS_DIR, newName);
    try { fs.renameSync(req.file.path, newPath); } catch { fs.copyFileSync(req.file.path, newPath); fs.unlinkSync(req.file.path); }
    await getDB().query('UPDATE users SET profile_pic=$1 WHERE id=$2', [newName, req.user.id]);
    res.json({ filename: newName });
  } catch (e) { next(e); }
});

// GET /api/users/profile-pic/:filename — serve profile pic
router.get('/profile-pic/:filename', clientAuth, (req, res) => {
  const fp = path.join(PICS_DIR, path.basename(req.params.filename));
  if (!fs.existsSync(fp)) return res.status(404).end();
  res.sendFile(fp);
});

// DELETE /api/users/me/profile-pic — delete own profile pic
router.delete('/me/profile-pic', clientAuth, async (req, res, next) => {
  try {
    const db   = getDB();
    const { rows } = await db.query('SELECT profile_pic FROM users WHERE id=$1', [req.user.id]);
    const user = rows[0];
    if (user?.profile_pic) {
      try { fs.unlinkSync(path.join(PICS_DIR, user.profile_pic)); } catch {}
    }
    await db.query('UPDATE users SET profile_pic=NULL WHERE id=$1', [req.user.id]);
    res.json({ ok: true });
  } catch (e) { next(e); }
});

module.exports = router;
