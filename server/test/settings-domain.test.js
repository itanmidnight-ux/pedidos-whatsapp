'use strict';
const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('settings-domain');
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

test('server_domain acepta un dominio valido sin protocolo', async () => {
  const token = await loginAdmin();
  const put = await request(app).put('/api/settings').set('Authorization', `Bearer ${token}`)
    .send({ key: 'server_domain', value: 'midominio.com' });
  expect(put.status).toBe(200);
  const get = await request(app).get('/api/settings').set('Authorization', `Bearer ${token}`);
  expect(get.body.settings.server_domain).toBe('midominio.com');
});

test('server_domain limpia el protocolo si el usuario lo pega igual', async () => {
  const token = await loginAdmin();
  const put = await request(app).put('/api/settings').set('Authorization', `Bearer ${token}`)
    .send({ key: 'server_domain', value: 'https://otrodominio.com' });
  expect(put.status).toBe(200);
});

test('server_domain rechaza mas de un dominio', async () => {
  const token = await loginAdmin();
  const put = await request(app).put('/api/settings').set('Authorization', `Bearer ${token}`)
    .send({ key: 'server_domain', value: 'uno.com,dos.com' });
  expect(put.status).toBe(400);
});

test('server_domain rechaza formato invalido', async () => {
  const token = await loginAdmin();
  const put = await request(app).put('/api/settings').set('Authorization', `Bearer ${token}`)
    .send({ key: 'server_domain', value: 'no es un dominio' });
  expect(put.status).toBe(400);
});

test('extra_domains acepta varios dominios separados por coma', async () => {
  const token = await loginAdmin();
  const put = await request(app).put('/api/settings').set('Authorization', `Bearer ${token}`)
    .send({ key: 'extra_domains', value: 'uno.duckdns.org, dos.ts.net' });
  expect(put.status).toBe(200);
  const get = await request(app).get('/api/settings').set('Authorization', `Bearer ${token}`);
  expect(get.body.settings.extra_domains).toBe('uno.duckdns.org, dos.ts.net');
});

test('extra_domains vacio es valido (deshabilita adicionales)', async () => {
  const token = await loginAdmin();
  const put = await request(app).put('/api/settings').set('Authorization', `Bearer ${token}`)
    .send({ key: 'extra_domains', value: '' });
  expect(put.status).toBe(200);
});

test('CORS: origin en server_domain es aceptado', async () => {
  const token = await loginAdmin();
  await request(app).put('/api/settings').set('Authorization', `Bearer ${token}`)
    .send({ key: 'server_domain', value: 'cors-test-domain.com' });
  const res = await request(app).get('/health').set('Origin', 'https://cors-test-domain.com');
  expect(res.status).toBe(200);
  expect(res.headers['access-control-allow-origin']).toBe('https://cors-test-domain.com');
});

test('CORS: origin desconocido sigue siendo rechazado', async () => {
  const res = await request(app).get('/health').set('Origin', 'https://no-deberia-pasar.com');
  expect(res.status).toBe(500);
});
