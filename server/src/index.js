'use strict';
const app = require('./app');
const { initDB, closeDB } = require('./db/database');
const { schedulePDFJob } = require('./services/pdfScheduler');
const logger = require('./utils/logger');

const PORT = process.env.PORT || 3000;
// Por defecto solo localhost: el puerto de Node nunca debe ser alcanzable
// directo desde internet (nginx/cloudflared lo exponen). HOST=0.0.0.0 es
// opt-in explicito para quien sepa lo que hace (ej. contenedor con su propio
// firewall externo).
const HOST = process.env.HOST || '127.0.0.1';
initDB().then(() => {
  schedulePDFJob();
  if (process.env.NODE_ENV !== 'test') {
    require('./services/securityMonitor').startSecurityMonitor();
    require('./services/backupScheduler').scheduleBackupJob();
  }
  const server = app.listen(PORT, HOST, async () => {
    logger.info(`Servidor corriendo en ${HOST}:${PORT}`);
    if (process.env.BOT_ENABLED === 'true') {
      const { initBot } = require('./services/waBot');
      await initBot().catch(e => logger.error({ err: e.message }, '[bot] init error'));
    }
  });

  // Anti slow-loris / conexiones colgadas -- importante para aguantar miles
  // de clientes concurrentes sin agotar sockets del proceso. headersTimeout
  // SIEMPRE debe ser mayor que keepAliveTimeout (requisito de Node).
  server.keepAliveTimeout = 65_000;
  server.headersTimeout   = 66_000;
  server.requestTimeout   = 30_000;

  // Apagado ordenado: cada redeploy manda SIGTERM -- sin esto se arriesgaba
  // cortar una escritura a la DB a mitad o dejar la sesion de WhatsApp en
  // estado inconsistente. server.close() deja de aceptar conexiones nuevas
  // y espera a que terminen las que ya estaban en curso antes de cerrar la DB.
  let shuttingDown = false;
  function shutdown(signal) {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info(`[shutdown] ${signal} recibido, cerrando ordenadamente...`);
    server.close(() => {
      closeDB();
      logger.info('[shutdown] servidor y DB cerrados.');
      process.exit(0);
    });
    // Si algo queda colgado (conexion keep-alive que no cierra), forzar salida.
    setTimeout(() => process.exit(1), 10_000).unref();
  }
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT',  () => shutdown('SIGINT'));
}).catch(err => { logger.error({ err }, 'Error iniciando servidor'); process.exit(1); });
