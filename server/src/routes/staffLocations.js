'use strict';
const express = require('express');
const router  = express.Router();
const { staffAuth, adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');
const { readLocationHistory, appendLocationHistory } = require('../services/locationHistory');

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

  const db = getDB();
  const user = db.prepare('SELECT username, display_name, role FROM users WHERE id=?').get(req.user.id);

  // La DB solo guarda la posicion ACTUAL (una fila por user_id) -- el mapa
  // en vivo siempre lee la ubicacion real y fresca. El recorrido completo
  // no se acumula aqui: va a un JSON liviano aparte (ver locationHistory.js).
  db.prepare('DELETE FROM staff_locations WHERE user_id=?').run(req.user.id);
  db.prepare(
    `INSERT INTO staff_locations (user_id, lat, lng, accuracy) VALUES (?,?,?,?)`
  ).run(req.user.id, latN, lngN, Number.isFinite(accN) ? accN : null);

  appendLocationHistory(req.user.id, {
    name: user?.display_name || user?.username || 'Desconocido',
    username: user?.username || null,
    role: user?.role || null,
    lat: latN,
    lng: lngN,
    accuracy: Number.isFinite(accN) ? accN : null,
    recorded_at: new Date().toISOString(),
  });

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
    LEFT JOIN staff_locations sl ON sl.user_id = u.id
    WHERE u.role IN ('admin','worker') AND u.active = 1
    ORDER BY (sl.recorded_at IS NULL), sl.recorded_at DESC
  `).all();
  res.json({ staff });
});

// GET /api/staff-locations/:userId — historial de posiciones de un
// trabajador especifico (para el detalle: recorrido reciente). Viene del
// JSON liviano, no de la DB -- ver locationHistory.js.
router.get('/:userId', adminAuth, (req, res) => {
  const db = getDB();
  const userId = parseInt(req.params.userId, 10);
  const user = db.prepare(
    `SELECT id, username, display_name, role FROM users WHERE id=? AND role IN ('admin','worker')`
  ).get(userId);
  if (!user) return res.status(404).json({ error: 'Trabajador no encontrado' });

  const history = readLocationHistory(userId).slice(-200).reverse();

  const lastLogin = db.prepare(
    `SELECT logged_in_at, logged_out_at, device_info FROM login_events WHERE user_id=? ORDER BY id DESC LIMIT 1`
  ).get(userId);

  res.json({ user, history, last_login: lastLogin || null });
});

module.exports = router;
