'use strict';
const pino = require('pino');
const { Writable } = require('stream');

// Texto legible en consola durante desarrollo; JSON plano en producción
// para que journald/NSSM/logrotate lo puedan procesar sin parseo extra.
const isProd = process.env.NODE_ENV === 'production';
const isTest = process.env.NODE_ENV === 'test';

// Buffer circular en memoria para GET /api/bot/logs (pestaña Logs del panel) --
// se pierde al reiniciar el proceso, pero /var/log/pedidos-bot/server.log
// (StandardOutput de systemd) ya cubre la persistencia real.
const LOG_BUFFER_LINES = parseInt(process.env.LOG_BUFFER_LINES, 10) || 500;
const ringBuffer = [];

// pino-http registra el request/response completo (incluye Authorization:
// Bearer <jwt> y X-Api-Key) -- nunca debe llegar así al buffer que expone
// GET /api/bot/logs. Solo nos importa el resumen, no los headers crudos.
function pushToRing(line) {
  let entry;
  try {
    const parsed = JSON.parse(line);
    if (parsed.req || parsed.res) {
      entry = {
        time:  new Date(parsed.time).toISOString(),
        level: pino.levels.labels[parsed.level] || 'info',
        msg:   `${parsed.req?.method || ''} ${parsed.req?.url || ''} -> ${parsed.res?.statusCode ?? ''}`.trim(),
      };
    } else {
      entry = {
        time:  new Date(parsed.time).toISOString(),
        level: pino.levels.labels[parsed.level] || 'info',
        msg:   parsed.msg || '',
        ...Object.fromEntries(Object.entries(parsed).filter(([k]) => !['time', 'level', 'msg', 'pid', 'hostname', 'req', 'res', 'responseTime'].includes(k))),
      };
    }
  } catch {
    entry = { time: new Date().toISOString(), level: 'info', msg: line.trim() };
  }
  ringBuffer.push(entry);
  if (ringBuffer.length > LOG_BUFFER_LINES) ringBuffer.shift();
}

const ringStream = new Writable({
  write(chunk, _enc, cb) { pushToRing(chunk.toString()); cb(); },
});

function getRecentLogs() { return ringBuffer; }

const logger = pino(
  { level: process.env.LOG_LEVEL || (isTest ? 'silent' : isProd ? 'info' : 'debug') },
  pino.multistream([
    { stream: (isProd || isTest) ? process.stdout : require('pino-pretty')({ colorize: true, translateTime: 'HH:MM:ss', ignore: 'pid,hostname' }) },
    { stream: ringStream },
  ])
);

logger.getRecentLogs = getRecentLogs;
module.exports = logger;
