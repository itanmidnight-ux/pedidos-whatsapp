'use strict';
const cron = require('node-cron');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');
const { promisify } = require('util');
const execFileAsync = promisify(execFile);
const { getDB } = require('../db/database');
const { encryptFile } = require('../utils/backupCrypto');
const { raiseAlert } = require('../utils/securityAlert');
const logger = require('../utils/logger');

// Postgres es hoy el unico punto de verdad de todo el negocio -- sin
// backup, un disco corrupto borra pedidos, clientes, config del bot, todo.
// Backup diario via pg_dump (formato custom, -Fc) + verificacion real con
// pg_restore --list (confirma que el archivo es un dump valido y no esta
// truncado/corrupto -- no solo que "el archivo existe").
const BACKUP_DIR = process.env.BACKUP_DIR || '/var/lib/pedidos-bot/backups';
const BACKUP_RETENTION_DAYS = parseInt(process.env.BACKUP_RETENTION_DAYS, 10) || 14;

function pgEnv() {
  return {
    ...process.env,
    PGPASSWORD: process.env.PG_PASSWORD || '',
    PGHOST: process.env.PG_HOST || '127.0.0.1',
    PGPORT: String(process.env.PG_PORT || 5432),
    PGDATABASE: process.env.PG_DATABASE || 'supermercado',
    PGUSER: process.env.PG_USER || 'pedidosbot',
  };
}

async function runBackup() {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dest = path.join(BACKUP_DIR, `pedidos-${stamp}.dump`);

  const dumpArgs = process.env.DATABASE_URL
    ? [process.env.DATABASE_URL, '-Fc', '-f', dest, '--no-owner']
    : ['-Fc', '-f', dest, '--no-owner'];
  await execFileAsync('pg_dump', dumpArgs, { env: pgEnv() });

  // Verificacion real: pg_restore --list lee el TOC del dump sin restaurarlo
  // -- si el archivo esta truncado/corrupto, falla aca en vez de descubrirse
  // recien cuando ya se necesita restaurar (el peor momento posible).
  const { stdout } = await execFileAsync('pg_restore', ['--list', dest], { env: pgEnv() });
  const tocLines = stdout.split('\n').filter(l => l.trim()).length;
  const { rows } = await getDB().query('SELECT COUNT(*) AS c FROM users');
  const userCount = Number(rows[0].c);

  if (tocLines < 1 || userCount < 1) {
    fs.unlinkSync(dest);
    throw new Error(`backup invalido (toc_entries=${tocLines}, users=${userCount})`);
  }

  pruneOldBackups();
  logger.info({ dest, userCount, tocLines }, '[backup] backup diario verificado OK');

  // Cifrado local: encryptFile borra el .dump en claro tras escribir el .enc
  // completo -- nunca coexisten ambas copias en disco.
  const encPath = await encryptFile(dest);
  logger.info({ path: encPath }, '[backup] backup cifrado localmente (AES-256-GCM)');

  const remoteUrl = process.env.BACKUP_REMOTE_URL;
  if (remoteUrl) {
    // rclone debe estar instalado y configurado por el usuario (rclone config) --
    // si falla, se loguea como warning, NUNCA se aborta el backup (el archivo
    // cifrado local ya existe y es válido con o sin la copia offsite).
    execFile('rclone', ['copy', encPath, remoteUrl], (err) => {
      if (err) logger.warn({ err: err.message }, '[backup] copia offsite falló — backup sigue disponible localmente');
      else logger.info({ remoteUrl }, '[backup] copia offsite completada');
    });
  } else {
    logger.info('[backup] BACKUP_REMOTE_URL no configurada — backup queda solo cifrado localmente');
  }

  return encPath;
}

function pruneOldBackups() {
  const cutoff = Date.now() - BACKUP_RETENTION_DAYS * 86_400_000;
  let files;
  try { files = fs.readdirSync(BACKUP_DIR); } catch (_) { return; }
  for (const f of files) {
    if (!f.startsWith('pedidos-') || !f.endsWith('.dump.enc')) continue;
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
