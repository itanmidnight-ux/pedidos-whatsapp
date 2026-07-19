'use strict';
const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('settings-business-info');
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';

const request = require('supertest');
const { initDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(async () => { await teardownTestSchema(); });

async function loginAdmin() {
  const res = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}

test('empresa_nombre/empresa_descripcion/horario_atencion son editables', async () => {
  const token = await loginAdmin();
  for (const key of ['empresa_nombre', 'empresa_descripcion', 'horario_atencion']) {
    const put = await request(app).put('/api/settings').set('Authorization', `Bearer ${token}`).send({ key, value: `test-${key}` });
    expect(put.status).toBe(200);
  }
  const get = await request(app).get('/api/settings').set('Authorization', `Bearer ${token}`);
  expect(get.body.settings.empresa_nombre).toBe('test-empresa_nombre');
  expect(get.body.settings.empresa_descripcion).toBe('test-empresa_descripcion');
  expect(get.body.settings.horario_atencion).toBe('test-horario_atencion');
});

test('keys muertas (sin consumidor real) ya no son aceptadas', async () => {
  const token = await loginAdmin();
  for (const key of ['business_name', 'business_phone', 'delivery_message', 'greeting_message']) {
    const put = await request(app).put('/api/settings').set('Authorization', `Bearer ${token}`).send({ key, value: 'x' });
    expect(put.status).toBe(400);
  }
});
