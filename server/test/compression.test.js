'use strict';
const path = require('path');
const os = require('os');

const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('compression');
process.env.REPORTS_DIR = path.join(os.tmpdir(), `reports-compression-${Date.now()}`);

const request = require('supertest');
const { initDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(async () => { await teardownTestSchema(); });

test('respuestas grandes de /app se sirven comprimidas con gzip', async () => {
  const res = await request(app)
    .get('/app/main.dart.js')
    .set('Accept-Encoding', 'gzip');
  expect(res.status).toBe(200);
  expect(res.headers['content-encoding']).toBe('gzip');
});
