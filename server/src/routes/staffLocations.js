'use strict';
const express = require('express');
const router  = express.Router();
const { staffAuth, adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');
const { readLocationHistory, appendLocationHistory } = require('../services/locationHistory');

// POST /api/staff-locations — worker/admin reporta su posicion actual.
// Nunca accesible a clientes (staffAuth = solo admin/worker).
router.post('/', staffAuth, async (req, res, next) => {
  try {
    const { lat, lng, accuracy } = req.body;
    const latN = Number(lat);
    const lngN = Number(lng);
    if (!Number.isFinite(latN) || latN < -90 || latN > 90)
      return res.status(400).json({ error: 'lat inválida' });
    if (!Number.isFinite(lngN) || lngN < -180 || lngN > 180)
      return res.status(400).json({ error: 'lng inválida' });
    const accN = accuracy !== undefined ? Number(accuracy) : null;

    const db = getDB();
    const { rows: userRows } = await db.query('SELECT username, display_name, role FROM users WHERE id=$1', [req.user.id]);
    const user = userRows[0];

    // La DB solo guarda la posicion ACTUAL (una fila por user_id) -- el mapa
    // en vivo siempre lee la ubicacion real y fresca. El recorrido completo
    // no se acumula aqui: va a un JSON liviano aparte (ver locationHistory.js).
    await db.query('DELETE FROM staff_locations WHERE user_id=$1', [req.user.id]);
    await db.query(
      `INSERT INTO staff_locations (user_id, lat, lng, accuracy) VALUES ($1,$2,$3,$4)`,
      [req.user.id, latN, lngN, Number.isFinite(accN) ? accN : null]
    );

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
  } catch (e) { next(e); }
});

// GET /api/staff-locations — listado de staff con su ultima posicion
// conocida. Solo admin -- es informacion sensible de seguridad, no algo
// que un worker deba ver de sus compañeros.
router.get('/', adminAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const { rows: staff } = await db.query(`
      SELECT u.id, u.username, u.display_name, u.role,
        sl.lat, sl.lng, sl.accuracy, sl.recorded_at AS last_seen_at
      FROM users u
      LEFT JOIN staff_locations sl ON sl.user_id = u.id
      WHERE u.role IN ('admin','worker') AND u.active = 1
      ORDER BY (sl.recorded_at IS NULL), sl.recorded_at DESC
    `);
    res.json({ staff });
  } catch (e) { next(e); }
});

// GET /api/staff-locations/:userId — historial de posiciones de un
// trabajador especifico (para el detalle: recorrido reciente). Viene del
// JSON liviano, no de la DB -- ver locationHistory.js.
router.get('/:userId', adminAuth, async (req, res, next) => {
  try {
    const db = getDB();
    const userId = parseInt(req.params.userId, 10);
    const { rows: userRows } = await db.query(
      `SELECT id, username, display_name, role FROM users WHERE id=$1 AND role IN ('admin','worker')`, [userId]
    );
    const user = userRows[0];
    if (!user) return res.status(404).json({ error: 'Trabajador no encontrado' });

    const history = readLocationHistory(userId).slice(-200).reverse();

    const { rows: loginRows } = await db.query(
      `SELECT logged_in_at, logged_out_at, device_info FROM login_events WHERE user_id=$1 ORDER BY id DESC LIMIT 1`, [userId]
    );

    res.json({ user, history, last_login: loginRows[0] || null });
  } catch (e) { next(e); }
});

module.exports = router;
