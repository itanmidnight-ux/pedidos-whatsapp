'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');
const { execFile } = require('child_process');
const { promisify } = require('util');
const execFileAsync = promisify(execFile);

const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('backup-scheduler');
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
const BACKUP_DIR = path.join(os.tmpdir(), `backup-sched-dir-${Date.now()}-${Math.random().toString(36).slice(2)}`);
process.env.BACKUP_DIR = BACKUP_DIR;

const { initDB } = require('../src/db/database');
require('../src/app'); // fuerza init de rutas/env antes de tocar servicios
const { runBackup, pruneOldBackups } = require('../src/services/backupScheduler');
const { decryptFile } = require('../src/utils/backupCrypto');

beforeAll(async () => { await initDB(); });
afterAll(async () => {
  await teardownTestSchema();
  try { fs.rmSync(BACKUP_DIR, { recursive: true, force: true }); } catch (_) {}
});

describe('backupScheduler', () => {
  test('runBackup crea backup cifrado (.dump.enc) valido e integro, sin dejar el .dump en claro', async () => {
    const dest = await runBackup();
    expect(dest.endsWith('.dump.enc')).toBe(true);
    expect(fs.existsSync(dest)).toBe(true);
    expect(fs.existsSync(dest.slice(0, -'.enc'.length))).toBe(false);

    const restoredPath = dest.slice(0, -'.enc'.length) + '.restored';
    decryptFile(dest, restoredPath);

    // Verificacion equivalente a la vieja (abrir el backup y confirmar que
    // tiene datos) pero para el formato custom de pg_dump: pg_restore --list
    // lee el TOC sin necesitar restaurarlo a una base real.
    const { stdout } = await execFileAsync('pg_restore', ['--list', restoredPath]);
    expect(stdout).toMatch(/TABLE DATA.*\busers\b/);

    fs.unlinkSync(restoredPath);
  }, 30000);

  test('pruneOldBackups borra backups viejos, conserva recientes', () => {
    fs.mkdirSync(BACKUP_DIR, { recursive: true });
    const oldFile = path.join(BACKUP_DIR, 'pedidos-old.dump.enc');
    const freshFile = path.join(BACKUP_DIR, 'pedidos-fresh.dump.enc');
    fs.writeFileSync(oldFile, 'x');
    fs.writeFileSync(freshFile, 'x');
    const oldTime = (Date.now() - 20 * 86_400_000) / 1000;
    fs.utimesSync(oldFile, oldTime, oldTime);

    pruneOldBackups();

    expect(fs.existsSync(oldFile)).toBe(false);
    expect(fs.existsSync(freshFile)).toBe(true);
  });
});
