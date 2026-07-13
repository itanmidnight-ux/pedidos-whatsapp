'use strict';
const path = require('path');
const os = require('os');

const DB_PATH = path.join(os.tmpdir(), `jwt-revocation-test-${Date.now()}.db`);
process.env.DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'test-secret';
process.env.API_KEY = 'test-api-key';
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
process.env.NODE_ENV = 'test';

const request = require('supertest');
const fs = require('fs');
const { initDB, closeDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(() => {
  closeDB();
  for (const s of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + s); } catch (_) {} }
});

test('logout revoca el token: un request posterior con el mismo token da 401', async () => {
  const login = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  const token = login.body.token;
  expect(token).toBeTruthy();

  const before = await request(app).get('/api/products/').set('Authorization', `Bearer ${token}`);
  expect(before.status).toBe(200);

  await request(app).post('/api/auth/logout').set('Authorization', `Bearer ${token}`);

  const after = await request(app).get('/api/products/').set('Authorization', `Bearer ${token}`);
  expect(after.status).toBe(401);
});
