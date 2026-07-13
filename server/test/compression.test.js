'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

const DB_PATH = path.join(os.tmpdir(), `compression-test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`);
process.env.DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'test-secret';
process.env.API_KEY = 'test-api-key';
process.env.NODE_ENV = 'test';
process.env.REPORTS_DIR = path.join(os.tmpdir(), `reports-compression-${Date.now()}`);

const request = require('supertest');
const { initDB, closeDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(() => {
  closeDB();
  for (const s of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + s); } catch (_) {} }
});

test('respuestas grandes de /app se sirven comprimidas con gzip', async () => {
  const res = await request(app)
    .get('/app/main.dart.js')
    .set('Accept-Encoding', 'gzip');
  expect(res.status).toBe(200);
  expect(res.headers['content-encoding']).toBe('gzip');
});
