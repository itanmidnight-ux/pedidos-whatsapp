'use strict';
const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('orders-mine');
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';

const request = require('supertest');
const { initDB, getDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(async () => { await teardownTestSchema(); });

function normPhone(phone) { return '57' + phone; }

async function registerClient(phone, label) {
  return request(app).post('/api/auth/register').send({
    phone,
    password: 'password123',
    display_name: 'Cliente Mine',
    email: `${label}@example.com`,
    address: 'Calle de prueba 123',
  });
}

async function findOrCreateCustomer(db, phone, name) {
  const { rows } = await db.query('SELECT id FROM customers WHERE phone=$1', [phone]);
  if (rows[0]) return rows[0];
  const { rows: inserted } = await db.query('INSERT INTO customers (phone, name) VALUES ($1, $2) RETURNING id', [phone, name]);
  return inserted[0];
}

describe('GET /api/orders/mine', () => {
  test('devuelve solo los pedidos del cliente autenticado, mas recientes primero', async () => {
    await registerClient('3002220001', 'cliente_mine_a');
    const loginA = await request(app).post('/api/auth/token').send({ username: normPhone('3002220001'), password: 'password123' });
    const tokenA = loginA.body.token;

    await registerClient('3002220002', 'cliente_mine_b');
    const loginB = await request(app).post('/api/auth/token').send({ username: normPhone('3002220002'), password: 'password123' });
    const tokenB = loginB.body.token;

    const db = getDB();
    const custA = await findOrCreateCustomer(db, normPhone('3002220001'), 'A');
    const custB = await findOrCreateCustomer(db, normPhone('3002220002'), 'B');

    await db.query(`INSERT INTO orders (customer_id, product_name, status, requested_at)
      VALUES ($1, 'Prod A1', 'pending', to_char((now() AT TIME ZONE 'UTC') - INTERVAL '1 minute', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))`, [custA.id]);
    await db.query(`INSERT INTO orders (customer_id, product_name, status, requested_at) VALUES ($1, 'Prod A2', 'en_camino', now_iso())`, [custA.id]);
    await db.query(`INSERT INTO orders (customer_id, product_name, status, requested_at) VALUES ($1, 'Prod B1', 'pending', now_iso())`, [custB.id]);

    const res = await request(app).get('/api/orders/mine').set('Authorization', `Bearer ${tokenA}`);
    expect(res.status).toBe(200);
    expect(res.body.length).toBe(2);
    expect(res.body.every(o => o.phone === normPhone('3002220001'))).toBe(true);
    expect(res.body[0].product_name).toBe('Prod A2'); // mas reciente primero

    const resB = await request(app).get('/api/orders/mine').set('Authorization', `Bearer ${tokenB}`);
    expect(resB.body.length).toBe(1);
    expect(resB.body[0].product_name).toBe('Prod B1');
  });

  test('cliente sin pedidos recibe lista vacia', async () => {
    await registerClient('3002220003', 'cliente_mine_c');
    const login = await request(app).post('/api/auth/token').send({ username: normPhone('3002220003'), password: 'password123' });
    const res = await request(app).get('/api/orders/mine').set('Authorization', `Bearer ${login.body.token}`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });
});
