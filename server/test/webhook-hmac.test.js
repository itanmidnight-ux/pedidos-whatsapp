'use strict';
const crypto = require('crypto');

const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('webhook-hmac');
process.env.WEBHOOK_SECRET = 'test-webhook-secret';

const request = require('supertest');
const { initDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(async () => { await teardownTestSchema(); });

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
