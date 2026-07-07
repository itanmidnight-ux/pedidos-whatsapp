const cron = require('node-cron');
const { generateDailyPDF } = require('./pdfGenerator');
const { getDB } = require('../db/database');
const logger = require('../utils/logger');

const RETENTION_DAYS = parseInt(process.env.ORDER_RETENTION_DAYS, 10) || 90;

// Los pedidos entregados solo se borran de la DB operativa una vez que ya
// quedaron respaldados en un PDF diario (pdf_exported=1) — el PDF es el
// registro permanente, la DB es solo el estado operativo reciente.
function cleanupOldDeliveredOrders() {
  const result = getDB().prepare(`
    DELETE FROM orders
    WHERE status IN ('entregado','delivered')
      AND pdf_exported = 1
      AND datetime(requested_at) < datetime('now', ?)
  `).run(`-${RETENTION_DAYS} days`);
  if (result.changes > 0) logger.info({ count: result.changes, retentionDays: RETENTION_DAYS }, '[cleanup] pedidos entregados archivados');
}

function schedulePDFJob() {
  cron.schedule('59 23 * * *', async () => {
    logger.info('Generando PDF diario...');
    try {
      const path = await generateDailyPDF();
      logger.info({ path }, 'PDF completado');
      cleanupOldDeliveredOrders();
    } catch (err) {
      logger.error({ err: err.message }, 'Error PDF');
    }
  }, { timezone: 'America/Bogota' });
  logger.info('PDF scheduler activo (23:59 diario)');
}

module.exports = { schedulePDFJob, cleanupOldDeliveredOrders };
