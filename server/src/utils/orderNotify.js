'use strict';
const { getDB } = require('../db/database');
const logger = require('./logger');

// Reusa la misma cola que ya usa /api/messages/send y securityAlert.js
// (tabla messages, direction='outbound', sent=0) -- waBot.js pollOutbound
// ya la drena solo, cero codigo nuevo en el bot.
const STATUS_TEXT = {
  en_camino: order => `🛵 Tu pedido #${order.id} va en camino.`,
  entregado: order => `✅ Tu pedido #${order.id} fue entregado. ¡Gracias por tu compra!`,
  cancelled: order => `❌ Tu pedido #${order.id} fue cancelado.${order.cancel_reason ? ` Motivo: ${order.cancel_reason}` : ''}`,
};

function notifyOrderStatus(order) {
  const build = STATUS_TEXT[order.status];
  if (!build || !order.phone) return;

  const db = getDB();
  db.prepare(`
    INSERT INTO messages (phone, content, direction, sent, type)
    VALUES (?, ?, 'outbound', 0, 'order_status')
  `).run(order.phone, build(order));
  logger.info({ orderId: order.id, status: order.status }, '[orderNotify] notificacion encolada');
}

module.exports = { notifyOrderStatus };
