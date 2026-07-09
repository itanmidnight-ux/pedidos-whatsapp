'use strict';
const express = require('express');
const router  = express.Router();
const { adminAuth, clientAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');
const { encryptText, decryptText } = require('../utils/botCrypto');
const { sanitizeText } = require('../utils/sanitize');

// Nequi Conecta (pago push) todavia no tiene credenciales reales de API --
// esta es la infraestructura completa (guardado cifrado, conectar/pausar/
// reanudar/cambiar) lista para activar en cuanto lleguen. Sin api_key el
// "conectar" solo registra la cuenta receptora para mostrarla en el
// checkout de la app; el cobro real queda pendiente de integracion cuando
// haya convenio con Nequi/Bancolombia.

// Mismo formato usado en todo el proyecto (57 + 10 digitos) -- users.phone,
// customers.phone, etc.
function normalizeNequiPhone(raw) {
  const digits = String(raw || '').replace(/\D/g, '');
  if (digits.length === 10 && digits.startsWith('3')) return '57' + digits;
  if (digits.length === 12 && digits.startsWith('573')) return digits;
  return null;
}

// GET /api/payments/nequi — estado completo (solo admin, ve el numero real)
router.get('/nequi', adminAuth, (req, res) => {
  const row = getDB().prepare('SELECT * FROM nequi_config WHERE id=1').get();
  res.json({
    status: row?.status || 'disconnected',
    phone: row?.phone_encrypted ? decryptText(row.phone_encrypted) : null,
    account_name: row?.account_name || null,
    has_api_key: !!row?.api_key_encrypted,
    connected_at: row?.connected_at || null,
    updated_at: row?.updated_at || null,
  });
});

// POST /api/payments/nequi/connect — conecta (o cambia) la cuenta receptora
router.post('/nequi/connect', adminAuth, (req, res) => {
  const { phone, account_name, api_key } = req.body || {};
  const normPhone = normalizeNequiPhone(phone);
  if (!normPhone)
    return res.status(400).json({ error: 'Número de Nequi inválido (celular colombiano de 10 dígitos)' });
  if (!account_name || !String(account_name).trim())
    return res.status(400).json({ error: 'Nombre de la cuenta requerido' });

  const db = getDB();
  db.prepare(`
    UPDATE nequi_config SET
      phone_encrypted = ?, account_name = ?, api_key_encrypted = ?,
      status = 'connected', connected_at = datetime('now','localtime'),
      updated_at = datetime('now','localtime')
    WHERE id = 1
  `).run(
    encryptText(normPhone),
    sanitizeText(account_name, 100),
    api_key ? encryptText(String(api_key)) : null,
  );
  res.json({ ok: true });
});

// POST /api/payments/nequi/pause — deja de ofrecerse en el checkout sin
// perder la configuracion (para reanudar rapido despues)
router.post('/nequi/pause', adminAuth, (req, res) => {
  const db = getDB();
  const row = db.prepare('SELECT status FROM nequi_config WHERE id=1').get();
  if (!row || row.status === 'disconnected')
    return res.status(400).json({ error: 'No hay una cuenta Nequi conectada' });
  db.prepare(`UPDATE nequi_config SET status='paused', updated_at=datetime('now','localtime') WHERE id=1`).run();
  res.json({ ok: true });
});

// POST /api/payments/nequi/resume
router.post('/nequi/resume', adminAuth, (req, res) => {
  const db = getDB();
  const row = db.prepare('SELECT status, phone_encrypted FROM nequi_config WHERE id=1').get();
  if (!row || !row.phone_encrypted)
    return res.status(400).json({ error: 'No hay una cuenta Nequi configurada' });
  db.prepare(`UPDATE nequi_config SET status='connected', updated_at=datetime('now','localtime') WHERE id=1`).run();
  res.json({ ok: true });
});

// POST /api/payments/nequi/disconnect — borra todo (para "cambiar de cuenta"
// se desconecta y se vuelve a conectar con los datos nuevos)
router.post('/nequi/disconnect', adminAuth, (req, res) => {
  getDB().prepare(`
    UPDATE nequi_config SET
      phone_encrypted = NULL, account_name = NULL, api_key_encrypted = NULL,
      status = 'disconnected', connected_at = NULL, updated_at = datetime('now','localtime')
    WHERE id = 1
  `).run();
  res.json({ ok: true });
});

// GET /api/payments/methods — que opciones de pago mostrar en el checkout
// de la app cliente. Contra entrega siempre disponible; Nequi solo si esta
// 'connected' (no 'paused' ni 'disconnected'). El numero va completo -- es
// la cuenta RECEPTORA del negocio, el cliente lo necesita entero para
// poder transferir (no es un dato secreto, es como publicar una cuenta
// bancaria para que te paguen).
router.get('/methods', clientAuth, (req, res) => {
  const row = getDB().prepare('SELECT * FROM nequi_config WHERE id=1').get();
  const nequiAvailable = row?.status === 'connected' && !!row.phone_encrypted;
  res.json({
    contra_entrega: true,
    nequi: nequiAvailable ? {
      available: true,
      phone: decryptText(row.phone_encrypted),
      account_name: row.account_name,
    } : { available: false },
  });
});

module.exports = router;
