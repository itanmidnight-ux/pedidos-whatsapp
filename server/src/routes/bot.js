'use strict';
const express = require('express');
const router  = express.Router();
const { adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');
const logger = require('../utils/logger');

// GET /api/bot/status — estado del bot + cola pendiente (admin)
router.get('/status', adminAuth, (req, res) => {
  const pending = getDB().prepare(
    `SELECT COUNT(*) AS c FROM messages WHERE direction='outbound' AND sent=0`
  ).get().c;
  try {
    const { getStatus } = require('../services/waBot');
    res.json({ ...getStatus(), pendingQueue: pending });
  } catch (e) {
    res.json({ ready: false, hasQR: false, status: 'error', pendingQueue: pending, error: e.message });
  }
});

// GET /api/bot/qr — QR code como imagen PNG (admin)
router.get('/qr', adminAuth, (req, res) => {
  try {
    const { getQR } = require('../services/waBot');
    const qr = getQR();
    if (!qr) return res.status(404).json({ error: 'No hay QR pendiente — bot ya conectado, en pausa, o aún iniciando' });
    // qr es un data URL: "data:image/png;base64,..."
    const b64 = qr.split(',')[1];
    const buf = Buffer.from(b64, 'base64');
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Content-Length', buf.length);
    res.send(buf);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /api/bot/configure — { phone } vincula o cambia el número de la empresa
// (se encripta antes de guardarse). Si ya había otro número, cierra sesión
// vieja y pide QR nuevo.
router.post('/configure', adminAuth, async (req, res) => {
  const { phone } = req.body || {};
  if (!phone) return res.status(400).json({ error: 'phone requerido' });
  try {
    const { configurePhone } = require('../services/waBot');
    const result = await configurePhone(phone);
    res.json({ ok: true, ...result });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// POST /api/bot/pause — pausa la conexión (no desvincula el número)
router.post('/pause', adminAuth, async (req, res) => {
  try {
    const { pauseBot } = require('../services/waBot');
    await pauseBot();
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /api/bot/resume — reanuda la conexión pausada
router.post('/resume', adminAuth, async (req, res) => {
  try {
    const { resumeBot } = require('../services/waBot');
    await resumeBot();
    res.json({ ok: true });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// POST /api/bot/logout — desvincula por completo (requiere nuevo número + QR)
router.post('/logout', adminAuth, async (req, res) => {
  try {
    const { logoutBot } = require('../services/waBot');
    await logoutBot();
    getDB().prepare(
      `UPDATE bot_config SET phone_encrypted = NULL, status = 'disconnected', paused = 0,
       updated_at = (datetime('now','localtime')) WHERE id = 1`
    ).run();
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// GET /api/bot/logs — últimas líneas del bot (buffer circular en memoria,
// filtradas a solo lo relevante del bot -- no el tráfico HTTP general)
router.get('/logs', adminAuth, (req, res) => {
  const limit = Math.min(parseInt(req.query.limit, 10) || 200, 500);
  const logs = (logger.getRecentLogs?.() || []).filter(l => l.msg?.startsWith('[bot]')).slice(-limit);
  res.json({ logs });
});

module.exports = router;
