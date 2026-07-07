'use strict';
const express = require('express');
const router  = express.Router();
const { adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

// GET /api/bot/status — estado del bot + cola pendiente (admin)
router.get('/status', adminAuth, (req, res) => {
  const pending = getDB().prepare(
    `SELECT COUNT(*) AS c FROM messages WHERE direction='outbound' AND sent=0`
  ).get().c;
  try {
    const { getStatus } = require('../services/waBot');
    res.json({ ...getStatus(), pendingQueue: pending });
  } catch {
    res.json({ ready: false, hasQR: false, pendingQueue: pending });
  }
});

// GET /api/bot/qr — QR code como imagen PNG (admin — vincular el QR da control total de la sesión de WhatsApp)
router.get('/qr', adminAuth, (req, res) => {
  try {
    const { getQR } = require('../services/waBot');
    const qr = getQR();
    if (!qr) return res.status(404).json({ error: 'No hay QR pendiente — bot ya conectado o aún iniciando' });
    // qr is a data URL: "data:image/png;base64,..."
    const b64  = qr.split(',')[1];
    const buf  = Buffer.from(b64, 'base64');
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Content-Length', buf.length);
    res.send(buf);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /api/bot/restart — reiniciar bot (admin)
router.post('/restart', adminAuth, async (req, res) => {
  if (process.env.BOT_ENABLED !== 'true')
    return res.status(400).json({ error: 'Bot desactivado (BOT_ENABLED=false)' });
  try {
    const { initBot } = require('../services/waBot');
    await initBot();
    res.json({ ok: true, message: 'Bot reiniciado' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
