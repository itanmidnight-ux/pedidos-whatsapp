'use strict';
const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('perf-fixes');
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';

const request = require('supertest');
const { initDB, getDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(async () => { await teardownTestSchema(); });

async function loginAdmin() {
  const res = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}
async function registerClient(phone, label) {
  return request(app).post('/api/auth/register').send({
    phone, password: 'password123', display_name: 'Cliente Test',
    email: `${label}@example.com`, address: 'Calle de prueba 123',
  });
}

describe('chat.js: pedido de un solo producto queda en order_items', () => {
  test('_createOrder (via flujo "falta direccion") inserta orders + order_items', async () => {
    const adminToken = await loginAdmin();
    const product = await request(app).post('/api/products').set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Concentrado Perro 20kg', price: 80000 });

    await registerClient('3002220001', 'cliente_chat_pedido');
    const login = await request(app).post('/api/auth/token').send({ username: '573002220001', password: 'password123' });
    const clientToken = login.body.token;
    const db = getDB();

    // Simula estado "ya identificamos el producto, falta la direccion" --
    // evita depender del parser NLP (no deterministico) para este test.
    const username = '573002220001';
    await db.query(`INSERT INTO pending_orders (phone, product_id, product_name, missing_field) VALUES ($1, $2, $3, 'address')`,
      [`app:${username}`, product.body.id, product.body.name]);

    const res = await request(app).post('/api/chat/message').set('Authorization', `Bearer ${clientToken}`)
      .send({ message: 'Calle 45 #12-30, barrio centro' });
    expect(res.status).toBe(200);
    expect(res.body.order_id).toBeDefined();

    const { rows: items } = await db.query('SELECT * FROM order_items WHERE order_id=$1', [res.body.order_id]);
    expect(items.length).toBe(1);
    expect(items[0].product_id).toBe(product.body.id);
  });
});

describe('users.js: borrar usuario con historial da error claro, no 500', () => {
  test('worker con pedido/login asociado no se puede borrar (409, no 500)', async () => {
    const adminToken = await loginAdmin();
    await request(app).post('/api/users').set('Authorization', `Bearer ${adminToken}`)
      .send({ username: 'worker_con_historial', password: 'password123', role: 'worker' });
    await request(app).post('/api/auth/token').send({ username: 'worker_con_historial', password: 'password123' });

    const db = getDB();
    const { rows: userRows } = await db.query(`SELECT id FROM users WHERE username='worker_con_historial'`);
    const user = userRows[0];
    const { rows: countRows } = await db.query(`SELECT COUNT(*) c FROM login_events WHERE user_id=$1`, [user.id]);
    expect(Number(countRows[0].c)).toBeGreaterThan(0);

    const res = await request(app).delete(`/api/users/${user.id}`).set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(409);
    expect(res.body.error).toContain('Desactívalo');
  });

  test('usuario sin historial sí se puede borrar normalmente', async () => {
    const adminToken = await loginAdmin();
    await request(app).post('/api/users').set('Authorization', `Bearer ${adminToken}`)
      .send({ username: 'worker_sin_historial', password: 'password123', role: 'worker' });
    const list = await request(app).get('/api/users').set('Authorization', `Bearer ${adminToken}`);
    const user = list.body.users.find(u => u.username === 'worker_sin_historial');
    const res = await request(app).delete(`/api/users/${user.id}`).set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
  });
});
