'use strict';
const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('seed-admin-security');
delete process.env.SEED_PASSWORD_JESUS;

const bcrypt = require('bcrypt');
const { initDB, getDB } = require('../src/db/database');

afterAll(async () => {
  await teardownTestSchema();
});

test('el admin jesus NUNCA se crea con password literal "jesus" cuando falta SEED_PASSWORD_JESUS', async () => {
  await initDB();
  const { rows } = await getDB().query('SELECT password_hash FROM users WHERE username = $1', ['jesus']);
  const isDefaultWeak = await bcrypt.compare('jesus', rows[0].password_hash);
  expect(isDefaultWeak).toBe(false);
});
