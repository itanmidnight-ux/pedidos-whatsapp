'use strict';
const cron = require('node-cron');
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const { getDB } = require('../db/database');
const { raiseAlert } = require('../utils/securityAlert');
const logger = require('../utils/logger');

// La DB (SQLite) es hoy el unico punto de verdad de todo el negocio --
// sin backup, un disco corrupto o un `rm` accidental borra pedidos,
// clientes, config del bot, todo. Backup diario + verificacion real de
// que el backup ABRE y responde una query (no solo "el archivo existe").
const BACKUP_DIR = process.env.BACKUP_DIR || '/var/lib/pedidos-bot/backups';
const BACKUP_RETENTION_DAYS = parseInt(process.env.BACKUP_RETENTION_DAYS, 10) || 14;

async function runBackup() {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dest = path.join(BACKUP_DIR, `pedidos-${stamp}.db`);

  await getDB().backup(dest);

  // Verificacion real: abrir el archivo de backup (no la DB en vivo) y
  // confirmar que SQLite lo puede leer y que tiene datos coherentes --
  // un backup corrupto/truncado sin esto se descubriria recien cuando
  // ya se necesita restaurar, que es el peor momento posible.
  const check = new Database(dest, { readonly: true });
  const integrity = check.pragma('integrity_check', { simple: true });
  const userCount = check.prepare('SELECT COUNT(*) c FROM users').get().c;
  check.close();

  if (integrity !== 'ok' || userCount < 1) {
    fs.unlinkSync(dest);
    throw new Error(`backup invalido (integrity_check=${integrity}, users=${userCount})`);
  }

  pruneOldBackups();
  logger.info({ dest, userCount }, '[backup] backup diario verificado OK');
  return dest;
}

function pruneOldBackups() {
  const cutoff = Date.now() - BACKUP_RETENTION_DAYS * 86_400_000;
  let files;
  try { files = fs.readdirSync(BACKUP_DIR); } catch (_) { return; }
  for (const f of files) {
    if (!f.startsWith('pedidos-') || !f.endsWith('.db')) continue;
    const fpath = path.join(BACKUP_DIR, f);
    try {
      if (fs.statSync(fpath).mtimeMs < cutoff) fs.unlinkSync(fpath);
    } catch (_) {}
  }
}

function scheduleBackupJob() {
  cron.schedule('30 3 * * *', async () => {
    try {
      await runBackup();
    } catch (err) {
      logger.error({ err: err.message }, '[backup] fallo el backup diario');
      raiseAlert('backup_failed', `Backup diario falló: ${err.message}`);
    }
  }, { timezone: 'America/Bogota' });
  logger.info(`Backup scheduler activo (03:30 diario, retención ${BACKUP_RETENTION_DAYS} días)`);
}

module.exports = { scheduleBackupJob, runBackup, pruneOldBackups };
