'use strict';
const app = require('./app');
const { initDB } = require('./db/database');
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
  if (process.env.NODE_ENV !== 'test') require('./services/securityMonitor').startSecurityMonitor();
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
}).catch(err => { logger.error({ err }, 'Error iniciando servidor'); process.exit(1); });
