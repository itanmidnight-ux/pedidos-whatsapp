#!/usr/bin/env node
// Verifica que el servidor y dependencias estén activos
// Uso: node scripts/healthcheck.js
// Exit 0=OK, 1=fallo

const http   = require('http');
const https  = require('https');
const path   = require('path');

require('dotenv').config({ path: path.join(__dirname, '../.env') });

const PORT   = process.env.PORT || 3000;
const DOMAIN = process.env.NGROK_DOMAIN;

function check(url) {
  return new Promise((resolve) => {
    const mod = url.startsWith('https') ? https : http;
    const req = mod.get(url, { timeout: 5000 }, (res) => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve({ ok: res.statusCode === 200, status: res.statusCode, body: d.slice(0, 100) }));
    });
    req.on('error', e => resolve({ ok: false, error: e.message }));
    req.on('timeout', () => { req.destroy(); resolve({ ok: false, error: 'timeout' }); });
  });
}

async function main() {
  const checks = [
    { name: 'Server local',  url: `http://localhost:${PORT}/health` },
  ];
  if (DOMAIN) checks.push({ name: 'ngrok tunnel', url: `https://${DOMAIN}/health` });

  let allOk = true;
  for (const c of checks) {
    const r = await check(c.url);
    const icon = r.ok ? '✓' : '✗';
    console.log(`${icon} ${c.name}: ${r.ok ? 'OK' : (r.error || `HTTP ${r.status}`)}`);
    if (!r.ok) allOk = false;
  }

  if (allOk) { console.log('\n✅ Sistema funcionando correctamente'); process.exit(0); }
  else        { console.log('\n❌ Hay problemas — revisa los logs');    process.exit(1); }
}

main();
