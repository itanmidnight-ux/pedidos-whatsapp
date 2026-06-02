'use strict';
const express = require('express');
const router  = express.Router();
const { adminAuth } = require('../middleware/auth');

// GET /api/bot/status — estado del bot (admin)
router.get('/status', adminAuth, (req, res) => {
  try {
    const { getStatus } = require('../services/waBot');
    res.json(getStatus());
  } catch {
    res.json({ ready: false, provider: process.env.BOT_ENABLED === 'true' ? 'baileys' : 'disabled' });
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
