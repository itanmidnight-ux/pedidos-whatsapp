'use strict';
const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('orders-no-bulk-delete');
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';

const request = require('supertest');
const { initDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(async () => { await teardownTestSchema(); });

test('DELETE /api/orders/bulk ya no existe (eliminado permanentemente)', async () => {
  const login = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  const res = await request(app).delete('/api/orders/bulk').set('Authorization', `Bearer ${login.body.token}`).send({ all: true });
  expect(res.status).toBe(404);
});
