'use strict';
const { getDB } = require('../db/database');
const { sanitizeText } = require('./sanitize');
const logger = require('./logger');

// Reusa la MISMA cola que ya usa /api/messages/send (tabla messages,
// direction='outbound', sent=0) -- el bot de WhatsApp (waBot.js pollOutbound)
// ya la drena solo, cero codigo nuevo en el bot para que esto funcione.
// Se llama sin await desde auth.js (recordFail) -- atrapa sus propios
// errores para no dejar una promesa rechazada sin manejar en medio del
// flujo de login.
async function raiseAlert(kind, message) {
  try {
    const db = getDB();
    await db.query(`INSERT INTO security_alerts (kind, message) VALUES ($1, $2)`,
      [kind, sanitizeText(message, 500)]);

    const { rows } = await db.query(`SELECT phone FROM users WHERE role = 'admin' AND phone IS NOT NULL LIMIT 1`);
    const admin = rows[0];
    if (!admin) {
      logger.warn({ kind }, '[security] alerta generada pero ningun admin tiene celular registrado -- no se envia WhatsApp');
      return;
    }
    await db.query(`
      INSERT INTO messages (phone, content, direction, sent, type)
      VALUES ($1, $2, 'outbound', 0, 'security_alert')
    `, [admin.phone, `🔒 Alerta de seguridad: ${message}`]);
  } catch (e) {
    logger.error({ err: e.message, kind }, '[security] fallo al generar alerta');
  }
}

module.exports = { raiseAlert };
