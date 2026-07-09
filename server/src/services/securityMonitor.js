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

function scanSuspiciousIPs() {
  const rows = getDB().prepare(`
    SELECT ip,
           SUM(requests)  AS requests,
           SUM(count_401) + SUM(count_403) AS auth_fails,
           SUM(count_404) AS scans
    FROM ip_activity
    WHERE minute >= ?
    GROUP BY ip
  `).all(new Date(Date.now() - 5 * 60_000).toISOString().slice(0, 16));

  for (const row of rows) {
    const isSuspicious = row.requests > REQUESTS_THRESHOLD
      || row.auth_fails >= AUTH_FAIL_THRESHOLD
      || row.scans >= SCAN_THRESHOLD;
    if (!isSuspicious) continue;

    const last = lastAlertedAt.get(row.ip) || 0;
    if (Date.now() - last < ALERT_COOLDOWN_MS) continue;
    lastAlertedAt.set(row.ip, Date.now());

    raiseAlert('ip_flagged',
      `IP ${row.ip} con comportamiento sospechoso: ${row.requests} requests, ${row.auth_fails} fallos de auth, ${row.scans} rutas no encontradas (últimos 5 min)`);
  }
}

function startSecurityMonitor() {
  setInterval(scanSuspiciousIPs, 60_000).unref();
}

module.exports = { startSecurityMonitor, scanSuspiciousIPs };
