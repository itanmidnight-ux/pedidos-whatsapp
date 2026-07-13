'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

process.env.BACKUP_ENCRYPTION_KEY = 'test-backup-key-do-not-use-in-prod';

const { encryptFile, decryptFile } = require('../src/utils/backupCrypto');

test('encryptFile cifra el archivo, borra el original, y decryptFile recupera el contenido exacto', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'backup-crypto-test-'));
  const srcPath = path.join(dir, 'test.db');
  const original = Buffer.from('contenido de prueba del backup 🔒');
  fs.writeFileSync(srcPath, original);

  const encPath = await encryptFile(srcPath);

  expect(fs.existsSync(srcPath)).toBe(false);
  expect(fs.existsSync(encPath)).toBe(true);
  expect(fs.readFileSync(encPath).equals(original)).toBe(false);

  const restoredPath = path.join(dir, 'restored.db');
  decryptFile(encPath, restoredPath);
  expect(fs.readFileSync(restoredPath).equals(original)).toBe(true);

  fs.rmSync(dir, { recursive: true, force: true });
});

test('encryptFile no deja .enc parcial ni borra el .db si falla la escritura', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'backup-crypto-test-'));
  const srcPath = path.join(dir, 'test.db');
  const original = Buffer.from('contenido de prueba del backup 🔒');
  fs.writeFileSync(srcPath, original);

  const spy = jest.spyOn(fs, 'writeFileSync').mockImplementationOnce(() => {
    throw new Error('ENOSPC simulated');
  });

  await expect(encryptFile(srcPath)).rejects.toThrow('ENOSPC simulated');

  spy.mockRestore();

  expect(fs.existsSync(srcPath)).toBe(true);
  expect(fs.existsSync(srcPath + '.enc')).toBe(false);
  expect(fs.existsSync(srcPath + '.enc.tmp')).toBe(false);
  expect(fs.readFileSync(srcPath).equals(original)).toBe(true);

  fs.rmSync(dir, { recursive: true, force: true });
});
