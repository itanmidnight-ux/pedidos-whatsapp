'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

const DB_PATH = path.join(os.tmpdir(), `orders-no-delete-test-${Date.now()}.db`);
process.env.DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'test-secret';
process.env.API_KEY = 'test-api-key';
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
process.env.NODE_ENV = 'test';

const request = require('supertest');
const { initDB, closeDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(() => {
  closeDB();
  for (const s of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + s); } catch (_) {} }
});

test('DELETE /api/orders/bulk ya no existe (eliminado permanentemente)', async () => {
  const login = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  const res = await request(app).delete('/api/orders/bulk').set('Authorization', `Bearer ${login.body.token}`).send({ all: true });
  expect(res.status).toBe(404);
});
