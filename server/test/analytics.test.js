'use strict';
const path = require('path');
const fs = require('fs');
const os = require('os');

const DB_PATH = path.join(os.tmpdir(), `pedidos-test-analytics-${Date.now()}.db`);
process.env.DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'test-secret';
process.env.API_KEY = 'test-api-key';
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
process.env.NODE_ENV = 'test';

const request = require('supertest');
const { initDB, closeDB, getDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => {
  await initDB();
  const db = getDB();
  db.prepare(`INSERT INTO customers (phone, name) VALUES ('573000000001','Cliente Uno')`).run();
  const cust = db.prepare(`SELECT id FROM customers WHERE phone='573000000001'`).get();
  db.prepare(`INSERT INTO orders (customer_id, product_name, status, delivered_at, requested_at)
    VALUES (?, 'Concentrado 40kg', 'entregado', datetime('now'), datetime('now'))`).run(cust.id);
  const order = db.prepare(`SELECT id FROM orders WHERE customer_id=?`).get(cust.id);
  db.prepare(`INSERT INTO order_items (order_id, product_name, product_price, quantity) VALUES (?, 'Concentrado 40kg', 85000, 1)`).run(order.id);
  db.prepare(`INSERT INTO products (name, price, stock, low_stock_threshold) VALUES ('Concentrado 40kg', 85000, 3, 5)`).run();
});
afterAll(() => {
  closeDB();
  for (const suffix of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + suffix); } catch (_) {} }
});

async function loginAdmin() {
  const res = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}

describe('GET /api/analytics/*', () => {
  test('requiere admin', async () => {
    const res = await request(app).get('/api/analytics/summary');
    expect(res.status).toBe(401);
  });

  test('/summary devuelve totales', async () => {
    const token = await loginAdmin();
    const res = await request(app).get('/api/analytics/summary').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('sales_today');
    expect(res.body).toHaveProperty('avg_ticket');
    expect(res.body).toHaveProperty('cancelled_pct');
  });

  test('/products incluye alerta de stock bajo', async () => {
    const token = await loginAdmin();
    const res = await request(app).get('/api/analytics/products').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const low = res.body.low_stock.find(p => p.name === 'Concentrado 40kg');
    expect(low).toBeDefined();
    expect(low.stock).toBe(3);
  });

  test('/employees devuelve array', async () => {
    const token = await loginAdmin();
    const res = await request(app).get('/api/analytics/employees').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.employees)).toBe(true);
  });

  test('/customers devuelve nuevos y recurrentes', async () => {
    const token = await loginAdmin();
    const res = await request(app).get('/api/analytics/customers').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('new_customers');
    expect(res.body).toHaveProperty('returning_customers');
  });
});
