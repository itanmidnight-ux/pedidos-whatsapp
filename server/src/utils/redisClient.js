'use strict';
const logger = require('./logger');

// Redis es opcional y aditivo: si REDIS_URL no esta definida, o la conexion
// falla, todo lo que lo consume (rate-limit, cache de revocacion JWT) cae
// solo a su comportamiento anterior (memoria / tabla SQLite). Nunca debe
// ser un punto unico de fallo.
let client = null; // null = no inicializado, false = deshabilitado (sin REDIS_URL)

function getRedisClient() {
  if (client !== null) return client || null;
  if (!process.env.REDIS_URL) {
    client = false;
    return null;
  }
  const Redis = require('ioredis');
  client = new Redis(process.env.REDIS_URL, {
    maxRetriesPerRequest: 1,
    retryStrategy: (times) => Math.min(times * 500, 5000),
    lazyConnect: false,
  });
  client.on('error', (err) => logger.warn({ err: err.message }, '[redis] error de conexion'));
  client.on('ready', () => logger.info('[redis] conectado'));
  return client;
}

function isRedisReady() {
  return !!(client && client !== false && client.status === 'ready');
}

module.exports = { getRedisClient, isRedisReady };
