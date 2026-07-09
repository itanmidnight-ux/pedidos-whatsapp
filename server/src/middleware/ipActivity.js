'use strict';
const { getDB } = require('../db/database');
const { getIP } = require('../utils/ip');

// Buffer en memoria -- nunca se escribe a SQLite por-request (con miles de
// usuarios concurrentes eso seria un cuello de botella real). Se acumula
// aca y un flush periodico (cada 10s, ver startIpActivityFlusher) hace UN
// solo upsert por IP activa en esa ventana.
let buffer = new Map(); // ip -> { requests, count_401, count_403, count_404, last_path, last_user_agent }

function currentMinute() {
  return new Date().toISOString().slice(0, 16); // 'YYYY-MM-DDTHH:MM'
}

function ipActivityMiddleware(req, res, next) {
  const ip = getIP(req);
  res.on('finish', () => {
    const entry = buffer.get(ip) || { requests: 0, count_401: 0, count_403: 0, count_404: 0, last_path: null, last_user_agent: null };
    entry.requests += 1;
    if (res.statusCode === 401) entry.count_401 += 1;
    if (res.statusCode === 403) entry.count_403 += 1;
    if (res.statusCode === 404) entry.count_404 += 1;
    entry.last_path = req.originalUrl || req.url;
    entry.last_user_agent = req.headers['user-agent'] || null;
    buffer.set(ip, entry);
  });
  next();
}

// Vuelca el buffer actual a la tabla ip_activity y lo limpia. Exportada
// para que los tests puedan forzar un flush sin esperar el setInterval real.
function flushIpActivity() {
  if (buffer.size === 0) return;
  const minute = currentMinute();
  const toFlush = buffer;
  buffer = new Map();

  const db = getDB();
  const upsert = db.prepare(`
    INSERT INTO ip_activity (ip, minute, requests, count_401, count_403, count_404, last_path, last_user_agent)
    VALUES (@ip, @minute, @requests, @count_401, @count_403, @count_404, @last_path, @last_user_agent)
    ON CONFLICT(ip, minute) DO UPDATE SET
      requests        = requests + excluded.requests,
      count_401       = count_401 + excluded.count_401,
      count_403       = count_403 + excluded.count_403,
      count_404       = count_404 + excluded.count_404,
      last_path       = excluded.last_path,
      last_user_agent = excluded.last_user_agent
  `);
  const tx = db.transaction((entries) => {
    for (const [ip, e] of entries) {
      upsert.run({ ip, minute, ...e });
    }
  });
  tx([...toFlush.entries()]);
}

// Retencion: no tiene sentido guardar actividad de mas de un rato -- se
// borra lo viejo para que la tabla no crezca sin limite (mismo principio
// que la limpieza de media de 30 dias en waBot.js, aca la ventana es horas
// porque el proposito es deteccion en vivo, no historial largo).
function cleanupOldActivity() {
  getDB().prepare(`DELETE FROM ip_activity WHERE minute < ?`)
    .run(new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString().slice(0, 16));
}

function startIpActivityFlusher() {
  setInterval(flushIpActivity, 10_000).unref();
  setInterval(cleanupOldActivity, 30 * 60_000).unref();
}

module.exports = { ipActivityMiddleware, flushIpActivity, cleanupOldActivity, startIpActivityFlusher };
