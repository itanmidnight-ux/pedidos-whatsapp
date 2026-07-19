'use strict';
const { getDB, withTransaction } = require('../db/database');
const { getIP } = require('../utils/ip');
const logger = require('../utils/logger');

// Buffer en memoria -- nunca se escribe a Postgres por-request (con miles de
// usuarios concurrentes eso seria un cuello de botella real). Se acumula
// aca y un flush periodico (cada 10s, ver startIpActivityFlusher) hace UN
// solo upsert por IP activa en esa ventana.
let buffer = new Map(); // ip -> { requests, count_401, count_403, count_404, count_auth_fail, last_path, last_user_agent }

function currentMinute() {
  return new Date().toISOString().slice(0, 16); // 'YYYY-MM-DDTHH:MM'
}

// Login real (fuerza bruta) vs 401 generico (token expirado antes de
// refrescar, etc, normal en cualquier cliente de larga duracion) -- solo
// el primero es señal confiable de ataque.
function isLoginAttempt(path) {
  return path === '/api/auth/token' || path === '/api/auth/register';
}

function ipActivityMiddleware(req, res, next) {
  const ip = getIP(req);
  res.on('finish', () => {
    const entry = buffer.get(ip) || { requests: 0, count_401: 0, count_403: 0, count_404: 0, count_auth_fail: 0, last_path: null, last_user_agent: null };
    entry.requests += 1;
    if (res.statusCode === 401) entry.count_401 += 1;
    if (res.statusCode === 403) entry.count_403 += 1;
    if (res.statusCode === 404) entry.count_404 += 1;
    const path = (req.originalUrl || req.url || '').split('?')[0];
    if (isLoginAttempt(path) && (res.statusCode === 401 || res.statusCode === 429)) entry.count_auth_fail += 1;
    entry.last_path = req.originalUrl || req.url;
    entry.last_user_agent = req.headers['user-agent'] || null;
    buffer.set(ip, entry);
  });
  next();
}

// Vuelca el buffer actual a la tabla ip_activity y lo limpia. Exportada
// para que los tests puedan forzar un flush sin esperar el setInterval real.
async function flushIpActivity() {
  if (buffer.size === 0) return;
  const minute = currentMinute();
  const toFlush = buffer;
  buffer = new Map();

  await withTransaction(async (client) => {
    for (const [ip, e] of toFlush.entries()) {
      await client.query(`
        INSERT INTO ip_activity (ip, minute, requests, count_401, count_403, count_404, count_auth_fail, last_path, last_user_agent)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        ON CONFLICT(ip, minute) DO UPDATE SET
          requests        = ip_activity.requests + excluded.requests,
          count_401       = ip_activity.count_401 + excluded.count_401,
          count_403       = ip_activity.count_403 + excluded.count_403,
          count_404       = ip_activity.count_404 + excluded.count_404,
          count_auth_fail = ip_activity.count_auth_fail + excluded.count_auth_fail,
          last_path       = excluded.last_path,
          last_user_agent = excluded.last_user_agent
      `, [ip, minute, e.requests, e.count_401, e.count_403, e.count_404, e.count_auth_fail, e.last_path, e.last_user_agent]);
    }
  });
}

// Retencion: no tiene sentido guardar actividad de mas de un rato -- se
// borra lo viejo para que la tabla no crezca sin limite (mismo principio
// que la limpieza de media de 30 dias en waBot.js, aca la ventana es horas
// porque el proposito es deteccion en vivo, no historial largo).
async function cleanupOldActivity() {
  await getDB().query(`DELETE FROM ip_activity WHERE minute < $1`,
    [new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString().slice(0, 16)]);
}

function startIpActivityFlusher() {
  setInterval(() => { flushIpActivity().catch(e => logger.error({ err: e.message }, '[ipActivity] flush fallo')); }, 10_000).unref();
  setInterval(() => { cleanupOldActivity().catch(e => logger.error({ err: e.message }, '[ipActivity] cleanup fallo')); }, 30 * 60_000).unref();
}

module.exports = { ipActivityMiddleware, flushIpActivity, cleanupOldActivity, startIpActivityFlusher };
