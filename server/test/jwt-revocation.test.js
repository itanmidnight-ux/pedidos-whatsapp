'use strict';
const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('jwt-revocation');
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';

const request = require('supertest');
const { initDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(async () => { await teardownTestSchema(); });

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
