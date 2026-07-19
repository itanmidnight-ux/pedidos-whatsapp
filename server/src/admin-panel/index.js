'use strict';
require('dotenv').config();
const app = require('./app');
const logger = require('../utils/logger');

const PORT = process.env.ADMIN_PANEL_PORT || 3002;
// Bind HARDCODEADO a 127.0.0.1 -- a proposito, sin leer HOST de .env como
// el resto de servicios. El panel admin NUNCA debe quedar alcanzable desde
// otra interfaz de red, ni por error de configuracion. Acceso remoto real
// se resuelve con VPN (Tailscale) mas adelante, nunca abriendo este puerto.
const HOST = '127.0.0.1';

const server = app.listen(PORT, HOST, () => {
  logger.info(`Panel admin corriendo en ${HOST}:${PORT} (solo localhost)`);
});

let shuttingDown = false;
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info(`[admin-panel] ${signal} recibido, cerrando...`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10_000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));
