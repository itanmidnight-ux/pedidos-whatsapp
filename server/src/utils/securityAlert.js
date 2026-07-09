'use strict';
const { getDB } = require('../db/database');
const { sanitizeText } = require('./sanitize');
const logger = require('./logger');

// Reusa la MISMA cola que ya usa /api/messages/send (tabla messages,
// direction='outbound', sent=0) -- el bot de WhatsApp (waBot.js pollOutbound)
// ya la drena solo, cero codigo nuevo en el bot para que esto funcione.
function raiseAlert(kind, message) {
  const db = getDB();
  db.prepare(`INSERT INTO security_alerts (kind, message) VALUES (?, ?)`)
    .run(kind, sanitizeText(message, 500));

  const admin = db.prepare(`SELECT phone FROM users WHERE role = 'admin' AND phone IS NOT NULL LIMIT 1`).get();
  if (!admin) {
    logger.warn({ kind }, '[security] alerta generada pero ningun admin tiene celular registrado -- no se envia WhatsApp');
    return;
  }
  db.prepare(`
    INSERT INTO messages (phone, content, direction, sent, type)
    VALUES (?, ?, 'outbound', 0, 'security_alert')
  `).run(admin.phone, `🔒 Alerta de seguridad: ${message}`);
}

module.exports = { raiseAlert };
