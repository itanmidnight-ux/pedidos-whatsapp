'use strict';
const path = require('path');
const os = require('os');

const DB_PATH = path.join(os.tmpdir(), `seed-admin-test-${Date.now()}.db`);
process.env.DB_PATH = DB_PATH;
process.env.NODE_ENV = 'test';
delete process.env.SEED_PASSWORD_JESUS;

const bcrypt = require('bcrypt');
const { initDB, getDB, closeDB } = require('../src/db/database');

afterAll(() => {
  closeDB();
  const fs = require('fs');
  for (const s of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + s); } catch (_) {} }
});

test('el admin jesus NUNCA se crea con password literal "jesus" cuando falta SEED_PASSWORD_JESUS', async () => {
  await initDB();
  const user = getDB().prepare('SELECT password_hash FROM users WHERE username = ?').get('jesus');
  const isDefaultWeak = await bcrypt.compare('jesus', user.password_hash);
  expect(isDefaultWeak).toBe(false);
});
