'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

const DB_PATH = path.join(os.tmpdir(), `upload-magic-test-${Date.now()}.db`);
process.env.DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'test-secret';
process.env.API_KEY = 'test-api-key';
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
process.env.NODE_ENV = 'test';
process.env.APPDATA = os.tmpdir();

const request = require('supertest');
const { initDB, closeDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(() => {
  closeDB();
  for (const s of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + s); } catch (_) {} }
});

async function loginStaff() {
  const res = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}

test('rechaza un ejecutable ELF renombrado a .jpg con Content-Type spoofeado', async () => {
  const token = await loginStaff();
  // Magic bytes reales de un ELF (0x7F 'E' 'L' 'F'), no una imagen -- esto
  // es exactamente el ataque que el hallazgo describe: octet-stream +
  // extension falsa.
  const elfBuffer = Buffer.from([0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]);
  const res = await request(app)
    .post('/api/messages/send-media')
    .set('Authorization', `Bearer ${token}`)
    .field('phone', '3001234567')
    .field('media_type', 'image')
    .attach('file', elfBuffer, { filename: 'foto.jpg', contentType: 'application/octet-stream' });
  expect(res.status).toBe(400);
});

test('acepta un JPEG real declarado correctamente', async () => {
  const token = await loginStaff();
  const jpegHeader = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
  const res = await request(app)
    .post('/api/messages/send-media')
    .set('Authorization', `Bearer ${token}`)
    .field('phone', '3001234567')
    .field('media_type', 'image')
    .attach('file', jpegHeader, { filename: 'foto.jpg', contentType: 'image/jpeg' });
  expect(res.status).toBe(200);
});
