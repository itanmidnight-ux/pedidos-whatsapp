'use strict';
require('dotenv').config();
const app = require('./app');
const logger = require('../utils/logger');

const PORT = process.env.PUBLIC_SITE_PORT || 3001;
// Igual que el server principal: solo localhost -- Cloudflare tunnel es
// quien lo expone hacia afuera (ver deploy-linux.sh, setup_cloudflared_named_tunnel).
const HOST = process.env.HOST || '127.0.0.1';

const server = app.listen(PORT, HOST, () => {
  logger.info(`Sitio público corriendo en ${HOST}:${PORT}`);
});

server.keepAliveTimeout = 65_000;
server.headersTimeout   = 66_000;

let shuttingDown = false;
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info(`[public-site] ${signal} recibido, cerrando...`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10_000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));
