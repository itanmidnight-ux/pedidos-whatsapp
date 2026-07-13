'use strict';
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const fs = require('fs');

const DB_PATH = path.join(os.tmpdir(), `webhook-hmac-test-${Date.now()}.db`);
process.env.DB_PATH = DB_PATH;
process.env.API_KEY = 'test-api-key';
process.env.WEBHOOK_SECRET = 'test-webhook-secret';
process.env.NODE_ENV = 'test';

const request = require('supertest');
const { initDB, closeDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(() => {
  closeDB();
  for (const s of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + s); } catch (_) {} }
});

function sign(body, ts) {
  return crypto.createHmac('sha256', process.env.WEBHOOK_SECRET)
    .update(JSON.stringify(body) + ':' + ts).digest('hex');
}

test('rechaza webhook sin firma HMAC', async () => {
  const body = { phone: '3001234567', message: 'hola' };
  const res = await request(app).post('/api/webhook/message')
    .set('X-API-Key', 'test-api-key')
    .send(body);
  expect(res.status).toBe(401);
});

test('rechaza webhook con timestamp fuera de la ventana de 5 minutos', async () => {
  const body = { phone: '3001234567', message: 'hola' };
  const oldTs = Date.now() - 6 * 60 * 1000;
  const res = await request(app).post('/api/webhook/message')
    .set('X-API-Key', 'test-api-key')
    .set('X-Baileys-Timestamp', String(oldTs))
    .set('X-Baileys-Signature', sign(body, oldTs))
    .send(body);
  expect(res.status).toBe(401);
});

test('acepta webhook con firma HMAC válida y timestamp reciente', async () => {
  const body = { phone: '3001234567', message: 'hola' };
  const ts = Date.now();
  const res = await request(app).post('/api/webhook/message')
    .set('X-API-Key', 'test-api-key')
    .set('X-Baileys-Timestamp', String(ts))
    .set('X-Baileys-Signature', sign(body, ts))
    .send(body);
  expect(res.status).not.toBe(401);
});
