'use strict';
const pino = require('pino');

// Texto legible en consola durante desarrollo; JSON plano en producción
// para que journald/NSSM/logrotate lo puedan procesar sin parseo extra.
const isProd = process.env.NODE_ENV === 'production';
const isTest = process.env.NODE_ENV === 'test';

const logger = pino({
  level: process.env.LOG_LEVEL || (isTest ? 'silent' : isProd ? 'info' : 'debug'),
  transport: (isProd || isTest) ? undefined : {
    target: 'pino-pretty',
    options: { colorize: true, translateTime: 'HH:MM:ss', ignore: 'pid,hostname' },
  },
});

module.exports = logger;
