'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

const DB_PATH = path.join(os.tmpdir(), `backup-sched-${Date.now()}-${Math.random().toString(36).slice(2)}.db`);
const BACKUP_DIR = path.join(os.tmpdir(), `backup-sched-dir-${Date.now()}-${Math.random().toString(36).slice(2)}`);
process.env.DB_PATH = DB_PATH;
process.env.BACKUP_DIR = BACKUP_DIR;
process.env.JWT_SECRET = 'test-secret';
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
process.env.NODE_ENV = 'test';

const { initDB, closeDB } = require('../src/db/database');
require('../src/app'); // fuerza init de rutas/env antes de tocar servicios
const { runBackup, pruneOldBackups } = require('../src/services/backupScheduler');
const { decryptFile } = require('../src/utils/backupCrypto');

beforeAll(async () => { await initDB(); });
afterAll(() => {
  closeDB();
  for (const s of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + s); } catch (_) {} }
  try { fs.rmSync(BACKUP_DIR, { recursive: true, force: true }); } catch (_) {}
});

describe('backupScheduler', () => {
  test('runBackup crea backup cifrado (.enc) valido e integro, sin dejar el .db en claro', async () => {
    const dest = await runBackup();
    expect(dest.endsWith('.db.enc')).toBe(true);
    expect(fs.existsSync(dest)).toBe(true);
    expect(fs.existsSync(dest.slice(0, -'.enc'.length))).toBe(false);

    const restoredPath = dest.slice(0, -'.enc'.length) + '.restored';
    decryptFile(dest, restoredPath);

    const Database = require('better-sqlite3');
    const check = new Database(restoredPath, { readonly: true });
    expect(check.pragma('integrity_check', { simple: true })).toBe('ok');
    expect(check.prepare('SELECT COUNT(*) c FROM users').get().c).toBeGreaterThan(0);
    check.close();
    fs.unlinkSync(restoredPath);
  });

  test('pruneOldBackups borra backups viejos, conserva recientes', () => {
    fs.mkdirSync(BACKUP_DIR, { recursive: true });
    const oldFile = path.join(BACKUP_DIR, 'pedidos-old.db.enc');
    const freshFile = path.join(BACKUP_DIR, 'pedidos-fresh.db.enc');
    fs.writeFileSync(oldFile, 'x');
    fs.writeFileSync(freshFile, 'x');
    const oldTime = (Date.now() - 20 * 86_400_000) / 1000;
    fs.utimesSync(oldFile, oldTime, oldTime);

    pruneOldBackups();

    expect(fs.existsSync(oldFile)).toBe(false);
    expect(fs.existsSync(freshFile)).toBe(true);
  });
});
