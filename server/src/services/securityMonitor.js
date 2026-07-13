'use strict';
const { getDB } = require('../db/database');
const { raiseAlert } = require('../utils/securityAlert');

// Umbrales de "IP sospechosa" en ventana de 5 minutos -- mismo criterio
// aplicado en la pestaña Conexiones del dashboard.
const REQUESTS_THRESHOLD = 300;
const AUTH_FAIL_THRESHOLD = 5;
const SCAN_THRESHOLD = 10;
const ALERT_COOLDOWN_MS = 60 * 60_000; // no re-alertar la misma IP antes de 1h

const lastAlertedAt = new Map(); // ip -> timestamp

// IPs que nunca son un atacante externo -- localhost es el propio bot
// llamando a su webhook (waBot.js -> este mismo servidor).
const LOOPBACK_IPS = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1']);

function scanSuspiciousIPs() {
  const rows = getDB().prepare(`
    SELECT ip,
           SUM(requests)  AS requests,
           SUM(count_auth_fail) AS auth_fail_real,
           SUM(count_404) AS scans
    FROM ip_activity
    WHERE minute >= ?
    GROUP BY ip
  `).all(new Date(Date.now() - 5 * 60_000).toISOString().slice(0, 16));

  for (const row of rows) {
    if (LOOPBACK_IPS.has(row.ip)) continue;
    // count_auth_fail solo cuenta login fallido real (/api/auth/token,
    // /api/auth/register) -- un 401/403 generico (token expirado antes de
    // refrescar, recurso opcional que no existe) es trafico normal de
    // cualquier cliente de larga duracion, no señal de ataque. Contarlo
    // acá disparaba alertas falsas por uso normal de la app.
    const isSuspicious = row.requests > REQUESTS_THRESHOLD
      || row.auth_fail_real >= AUTH_FAIL_THRESHOLD
      || row.scans >= SCAN_THRESHOLD;
    if (!isSuspicious) continue;

    const last = lastAlertedAt.get(row.ip) || 0;
    if (Date.now() - last < ALERT_COOLDOWN_MS) continue;
    lastAlertedAt.set(row.ip, Date.now());

    raiseAlert('ip_flagged',
      `IP ${row.ip} con comportamiento sospechoso: ${row.requests} requests, ${row.auth_fail_real} logins fallidos, ${row.scans} rutas no encontradas (últimos 5 min)`);
  }
}

function startSecurityMonitor() {
  setInterval(scanSuspiciousIPs, 60_000).unref();
}

module.exports = { startSecurityMonitor, scanSuspiciousIPs };
