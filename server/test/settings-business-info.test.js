'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

const DB_PATH = path.join(os.tmpdir(), `settings-business-test-${Date.now()}.db`);
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
