'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

const DB_PATH = path.join(os.tmpdir(), `orders-mine-${Date.now()}-${Math.random().toString(36).slice(2)}.db`);
process.env.DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'test-secret';
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
process.env.NODE_ENV = 'test';

const request = require('supertest');
const { initDB, closeDB, getDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => { await initDB(); });
afterAll(() => {
  closeDB();
  for (const s of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + s); } catch (_) {} }
});

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

describe('GET /api/orders/mine', () => {
  test('devuelve solo los pedidos del cliente autenticado, mas recientes primero', async () => {
    await registerClient('3002220001', 'cliente_mine_a');
    const loginA = await request(app).post('/api/auth/token').send({ username: normPhone('3002220001'), password: 'password123' });
    const tokenA = loginA.body.token;

    await registerClient('3002220002', 'cliente_mine_b');
    const loginB = await request(app).post('/api/auth/token').send({ username: normPhone('3002220002'), password: 'password123' });
    const tokenB = loginB.body.token;

    const db = getDB();
    const custA = db.prepare(`SELECT id FROM customers WHERE phone=?`).get(normPhone('3002220001'))
      || { id: db.prepare(`INSERT INTO customers (phone, name) VALUES (?, 'A')`).run(normPhone('3002220001')).lastInsertRowid };
    const custB = db.prepare(`SELECT id FROM customers WHERE phone=?`).get(normPhone('3002220002'))
      || { id: db.prepare(`INSERT INTO customers (phone, name) VALUES (?, 'B')`).run(normPhone('3002220002')).lastInsertRowid };

    db.prepare(`INSERT INTO orders (customer_id, product_name, status, requested_at) VALUES (?, 'Prod A1', 'pending', datetime('now','localtime','-1 minute'))`).run(custA.id);
    db.prepare(`INSERT INTO orders (customer_id, product_name, status, requested_at) VALUES (?, 'Prod A2', 'en_camino', datetime('now','localtime'))`).run(custA.id);
    db.prepare(`INSERT INTO orders (customer_id, product_name, status, requested_at) VALUES (?, 'Prod B1', 'pending', datetime('now','localtime'))`).run(custB.id);

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
