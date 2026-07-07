'use strict';
const path = require('path');
const fs = require('fs');
const os = require('os');

const DB_PATH = path.join(os.tmpdir(), `pedidos-test-${Date.now()}-${Math.random().toString(36).slice(2)}.db`);
process.env.DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'test-secret';
process.env.API_KEY = 'test-api-key';
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
process.env.NODE_ENV = 'test';

const request = require('supertest');
const { initDB, closeDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => {
  await initDB();
});

afterAll(() => {
  closeDB();
  for (const suffix of ['', '-wal', '-shm']) {
    try { fs.unlinkSync(DB_PATH + suffix); } catch (_) {}
  }
});

async function loginAdmin() {
  const res = await request(app)
    .post('/api/auth/token')
    .send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}

async function registerClient(username) {
  return request(app).post('/api/auth/register').send({
    username,
    password: 'password123',
    display_name: 'Cliente Test',
    email: `${username}@example.com`,
    address: 'Calle de prueba 123',
  });
}

describe('Registro de clientes queda pendiente de aprobación', () => {
  test('registro exitoso no devuelve token de sesión', async () => {
    const res = await registerClient('cliente_pendiente');
    expect(res.status).toBe(201);
    expect(res.body.token).toBeUndefined();
    expect(res.body.pending).toBe(true);
  });

  test('login falla mientras la cuenta no esté aprobada', async () => {
    await registerClient('cliente_pendiente2');
    const res = await request(app)
      .post('/api/auth/token')
      .send({ username: 'cliente_pendiente2', password: 'password123' });
    expect(res.status).toBe(401);
  });

  test('tras aprobación del admin, el login funciona', async () => {
    await registerClient('cliente_aprobado');
    const adminToken = await loginAdmin();
    const list = await request(app).get('/api/users').set('Authorization', `Bearer ${adminToken}`);
    const user = list.body.users.find(u => u.username === 'cliente_aprobado');
    expect(user).toBeDefined();

    await request(app)
      .put(`/api/users/${user.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ active: 1 });

    const login = await request(app)
      .post('/api/auth/token')
      .send({ username: 'cliente_aprobado', password: 'password123' });
    expect(login.status).toBe(200);
    expect(login.body.token).toBeDefined();
  });
});

describe('Control de acceso por rol (orders/messages son solo staff)', () => {
  let clientToken;
  let adminToken;

  beforeAll(async () => {
    adminToken = await loginAdmin();
    await registerClient('cliente_rol');
    const list = await request(app).get('/api/users').set('Authorization', `Bearer ${adminToken}`);
    const user = list.body.users.find(u => u.username === 'cliente_rol');
    await request(app).put(`/api/users/${user.id}`).set('Authorization', `Bearer ${adminToken}`).send({ active: 1 });
    const login = await request(app).post('/api/auth/token').send({ username: 'cliente_rol', password: 'password123' });
    clientToken = login.body.token;
  });

  test('cliente no puede leer pedidos', async () => {
    const res = await request(app).get('/api/orders').set('Authorization', `Bearer ${clientToken}`);
    expect(res.status).toBe(403);
  });

  test('cliente no puede leer conversaciones de WhatsApp', async () => {
    const res = await request(app).get('/api/messages').set('Authorization', `Bearer ${clientToken}`);
    expect(res.status).toBe(403);
  });

  test('cliente no puede enviar mensajes de WhatsApp arbitrarios', async () => {
    const res = await request(app)
      .post('/api/messages/send')
      .set('Authorization', `Bearer ${clientToken}`)
      .send({ phone: '573000000000', content: 'hola' });
    expect(res.status).toBe(403);
  });

  test('admin sí puede leer pedidos', async () => {
    const res = await request(app).get('/api/orders').set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
  });
});

describe('QR del bot requiere admin', () => {
  test('sin token → 401', async () => {
    const res = await request(app).get('/api/bot/qr');
    expect(res.status).toBe(401);
  });

  test('con token de admin → pasa la autenticación (404 si no hay QR pendiente)', async () => {
    const adminToken = await loginAdmin();
    const res = await request(app).get('/api/bot/qr').set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).not.toBe(401);
    expect(res.status).not.toBe(403);
  }, 20000); // primer require de whatsapp-web.js es lento
});

describe('GET /api/bot/status requiere admin y expone la cola pendiente', () => {
  test('sin token → 401', async () => {
    const res = await request(app).get('/api/bot/status');
    expect(res.status).toBe(401);
  });

  test('con token de admin → incluye pendingQueue', async () => {
    const adminToken = await loginAdmin();
    const res = await request(app).get('/api/bot/status').set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('pendingQueue');
    expect(typeof res.body.pendingQueue).toBe('number');
  });
});

describe('jwtAuth revalida active=1 contra la DB', () => {
  test('token de usuario desactivado deja de funcionar de inmediato', async () => {
    const adminToken = await loginAdmin();
    await registerClient('cliente_desactivar');
    const list = await request(app).get('/api/users').set('Authorization', `Bearer ${adminToken}`);
    const user = list.body.users.find(u => u.username === 'cliente_desactivar');
    await request(app).put(`/api/users/${user.id}`).set('Authorization', `Bearer ${adminToken}`).send({ active: 1 });
    const login = await request(app).post('/api/auth/token').send({ username: 'cliente_desactivar', password: 'password123' });
    const clientToken = login.body.token;

    await request(app).put(`/api/users/${user.id}`).set('Authorization', `Bearer ${adminToken}`).send({ active: 0 });

    const res = await request(app).get('/api/orders').set('Authorization', `Bearer ${clientToken}`);
    expect(res.status).toBe(401);
  });
});
