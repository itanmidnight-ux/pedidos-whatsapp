'use strict';
const express = require('express');
const router  = express.Router();
const { staffAuth, adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

// POST /api/staff-locations — worker/admin reporta su posicion actual.
// Nunca accesible a clientes (staffAuth = solo admin/worker).
router.post('/', staffAuth, (req, res) => {
  const { lat, lng, accuracy } = req.body;
  const latN = Number(lat);
  const lngN = Number(lng);
  if (!Number.isFinite(latN) || latN < -90 || latN > 90)
    return res.status(400).json({ error: 'lat inválida' });
  if (!Number.isFinite(lngN) || lngN < -180 || lngN > 180)
    return res.status(400).json({ error: 'lng inválida' });
  const accN = accuracy !== undefined ? Number(accuracy) : null;

  getDB().prepare(
    `INSERT INTO staff_locations (user_id, lat, lng, accuracy) VALUES (?,?,?,?)`
  ).run(req.user.id, latN, lngN, Number.isFinite(accN) ? accN : null);
  res.status(201).json({ ok: true });
});

// GET /api/staff-locations — listado de staff con su ultima posicion
// conocida. Solo admin -- es informacion sensible de seguridad, no algo
// que un worker deba ver de sus compañeros.
router.get('/', adminAuth, (req, res) => {
  const db = getDB();
  const staff = db.prepare(`
    SELECT u.id, u.username, u.display_name, u.role,
      sl.lat, sl.lng, sl.accuracy, sl.recorded_at AS last_seen_at
    FROM users u
    LEFT JOIN (
      SELECT sl1.user_id, sl1.lat, sl1.lng, sl1.accuracy, sl1.recorded_at
      FROM staff_locations sl1
      WHERE sl1.id = (SELECT MAX(sl2.id) FROM staff_locations sl2 WHERE sl2.user_id = sl1.user_id)
    ) sl ON sl.user_id = u.id
    WHERE u.role IN ('admin','worker') AND u.active = 1
    ORDER BY (sl.recorded_at IS NULL), sl.recorded_at DESC
  `).all();
  res.json({ staff });
});

// GET /api/staff-locations/:userId — historial de posiciones de un
// trabajador especifico (para el detalle: recorrido reciente).
router.get('/:userId', adminAuth, (req, res) => {
  const db = getDB();
  const userId = parseInt(req.params.userId, 10);
  const user = db.prepare(
    `SELECT id, username, display_name, role FROM users WHERE id=? AND role IN ('admin','worker')`
  ).get(userId);
  if (!user) return res.status(404).json({ error: 'Trabajador no encontrado' });

  const history = db.prepare(
    `SELECT lat, lng, accuracy, recorded_at FROM staff_locations WHERE user_id=? ORDER BY id DESC LIMIT 200`
  ).all(userId);

  const lastLogin = db.prepare(
    `SELECT logged_in_at, logged_out_at, device_info FROM login_events WHERE user_id=? ORDER BY id DESC LIMIT 1`
  ).get(userId);

  res.json({ user, history, last_login: lastLogin || null });
});

module.exports = router;
