'use strict';
const path = require('path');
const fs = require('fs');
const os = require('os');

const DB_PATH = path.join(os.tmpdir(), `pedidos-test-theming-${Date.now()}.db`);
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
  for (const suffix of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + suffix); } catch (_) {} }
});

async function loginAdmin() {
  const res = await request(app).post('/api/auth/token')
    .send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}

describe('Settings de theming', () => {
  test('GET /api/settings incluye theme_primary/theme_accent/theme_name por default', async () => {
    const token = await loginAdmin();
    const res = await request(app).get('/api/settings').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.settings.theme_primary).toBe('#2D5016');
    expect(res.body.settings.theme_accent).toBe('#D4800A');
  });

  test('PUT /api/settings actualiza theme_primary', async () => {
    const token = await loginAdmin();
    await request(app).put('/api/settings').set('Authorization', `Bearer ${token}`)
      .send({ key: 'theme_primary', value: '#1B4332' });
    const res = await request(app).get('/api/settings').set('Authorization', `Bearer ${token}`);
    expect(res.body.settings.theme_primary).toBe('#1B4332');
  });
});

describe('Logo de marca', () => {
  test('POST /api/settings/logo sin archivo -> 400', async () => {
    const token = await loginAdmin();
    const res = await request(app).post('/api/settings/logo')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });

  test('POST /api/settings/logo sin auth -> 401', async () => {
    const res = await request(app).post('/api/settings/logo');
    expect(res.status).toBe(401);
  });
});
