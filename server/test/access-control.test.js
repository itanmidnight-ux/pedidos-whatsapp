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

// El username ya no lo elige el cliente -- el registro lo deriva del
// celular (57 + 10 digitos). Cada test usa un celular de prueba distinto
// para no chocar con el indice UNIQUE de phone/username.
function normPhone(phone) { return '57' + phone; }

async function registerClient(phone, label) {
  return request(app).post('/api/auth/register').send({
    phone,
    password: 'password123',
    display_name: 'Cliente Test',
    email: `${label}@example.com`,
    address: 'Calle de prueba 123',
  });
}

describe('Registro de clientes queda activo de inmediato (sin aprobación manual)', () => {
  test('registro exitoso no devuelve token de sesión, pero la cuenta ya queda activa', async () => {
    const res = await registerClient('3001110001', 'cliente_activo');
    expect(res.status).toBe(201);
    expect(res.body.token).toBeUndefined();
    expect(res.body.pending).toBe(false);
  });

  test('login funciona de inmediato tras registrarse, sin intervención de un admin', async () => {
    await registerClient('3001110002', 'cliente_activo2');
    const res = await request(app)
      .post('/api/auth/token')
      .send({ username: normPhone('3001110002'), password: 'password123' });
    expect(res.status).toBe(200);
    expect(res.body.token).toBeDefined();
  });

  test('el cliente puede iniciar sesión escribiendo su celular tal cual lo registró (sin el 57)', async () => {
    await registerClient('3001110099', 'cliente_celular');
    const res = await request(app)
      .post('/api/auth/token')
      .send({ username: '3001110099', password: 'password123' });
    expect(res.status).toBe(200);
    expect(res.body.token).toBeDefined();
  });

  test('el cliente puede iniciar sesión con su correo en vez de su usuario', async () => {
    await registerClient('3001110003', 'cliente_correo');
    const res = await request(app)
      .post('/api/auth/token')
      .send({ username: 'cliente_correo@example.com', password: 'password123' });
    expect(res.status).toBe(200);
    expect(res.body.token).toBeDefined();
  });

  test('un admin sigue pudiendo desactivar la cuenta de un cliente manualmente', async () => {
    await registerClient('3001110004', 'cliente_a_desactivar');
    const adminToken = await loginAdmin();
    const list = await request(app).get('/api/users').set('Authorization', `Bearer ${adminToken}`);
    const user = list.body.users.find(u => u.username === normPhone('3001110004'));
    expect(user).toBeDefined();

    await request(app)
      .put(`/api/users/${user.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ active: 0 });

    const login = await request(app)
      .post('/api/auth/token')
      .send({ username: normPhone('3001110004'), password: 'password123' });
    expect(login.status).toBe(401);
  });
});

describe('Control de acceso por rol (orders/messages son solo staff)', () => {
  let clientToken;
  let adminToken;

  beforeAll(async () => {
    adminToken = await loginAdmin();
    await registerClient('3001110005', 'cliente_rol');
    const list = await request(app).get('/api/users').set('Authorization', `Bearer ${adminToken}`);
    const user = list.body.users.find(u => u.username === normPhone('3001110005'));
    await request(app).put(`/api/users/${user.id}`).set('Authorization', `Bearer ${adminToken}`).send({ active: 1 });
    const login = await request(app).post('/api/auth/token').send({ username: normPhone('3001110005'), password: 'password123' });
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

  test('cliente no puede reportar ni leer ubicaciones de staff', async () => {
    const post = await request(app).post('/api/staff-locations')
      .set('Authorization', `Bearer ${clientToken}`).send({ lat: 4.6, lng: -74.0 });
    expect(post.status).toBe(403);
    const get = await request(app).get('/api/staff-locations').set('Authorization', `Bearer ${clientToken}`);
    expect(get.status).toBe(403);
  });

  test('admin sí puede ver el listado de ubicaciones de staff', async () => {
    const res = await request(app).get('/api/staff-locations').set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.staff)).toBe(true);
  });

  test('worker puede reportar su ubicación pero no ver el listado completo', async () => {
    await request(app).post('/api/users').set('Authorization', `Bearer ${adminToken}`)
      .send({ username: 'worker_ubicacion', password: 'password123', role: 'worker' });
    const login = await request(app).post('/api/auth/token')
      .send({ username: 'worker_ubicacion', password: 'password123' });
    const workerToken = login.body.token;

    const post = await request(app).post('/api/staff-locations')
      .set('Authorization', `Bearer ${workerToken}`).send({ lat: 4.6, lng: -74.0 });
    expect(post.status).toBe(201);

    const get = await request(app).get('/api/staff-locations').set('Authorization', `Bearer ${workerToken}`);
    expect(get.status).toBe(403);
  });

  test('cliente no puede administrar Nequi pero sí ver los métodos de pago', async () => {
    const connect = await request(app).post('/api/payments/nequi/connect')
      .set('Authorization', `Bearer ${clientToken}`).send({ phone: '3001234567', account_name: 'Test' });
    expect(connect.status).toBe(403);

    const methods = await request(app).get('/api/payments/methods').set('Authorization', `Bearer ${clientToken}`);
    expect(methods.status).toBe(200);
    expect(methods.body.contra_entrega).toBe(true);
    expect(methods.body.nequi.available).toBe(false);
  });

  test('admin puede conectar Nequi y el checkout del cliente ve la cuenta completa', async () => {
    const connect = await request(app).post('/api/payments/nequi/connect')
      .set('Authorization', `Bearer ${adminToken}`).send({ phone: '3001234567', account_name: 'Monserrath' });
    expect(connect.status).toBe(200);

    const methods = await request(app).get('/api/payments/methods').set('Authorization', `Bearer ${clientToken}`);
    expect(methods.body.nequi.available).toBe(true);
    expect(methods.body.nequi.phone).toBe('573001234567');

    const pause = await request(app).post('/api/payments/nequi/pause').set('Authorization', `Bearer ${adminToken}`);
    expect(pause.status).toBe(200);
    const methodsAfterPause = await request(app).get('/api/payments/methods').set('Authorization', `Bearer ${clientToken}`);
    expect(methodsAfterPause.body.nequi.available).toBe(false);

    const disconnect = await request(app).post('/api/payments/nequi/disconnect').set('Authorization', `Bearer ${adminToken}`);
    expect(disconnect.status).toBe(200);
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
    await registerClient('3001110006', 'cliente_desactivar');
    const list = await request(app).get('/api/users').set('Authorization', `Bearer ${adminToken}`);
    const user = list.body.users.find(u => u.username === normPhone('3001110006'));
    await request(app).put(`/api/users/${user.id}`).set('Authorization', `Bearer ${adminToken}`).send({ active: 1 });
    const login = await request(app).post('/api/auth/token').send({ username: normPhone('3001110006'), password: 'password123' });
    const clientToken = login.body.token;

    await request(app).put(`/api/users/${user.id}`).set('Authorization', `Bearer ${adminToken}`).send({ active: 0 });

    const res = await request(app).get('/api/orders').set('Authorization', `Bearer ${clientToken}`);
    expect(res.status).toBe(401);
  });
});
