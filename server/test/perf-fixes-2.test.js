'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

const DB_PATH = path.join(os.tmpdir(), `perf-fixes-2-${Date.now()}-${Math.random().toString(36).slice(2)}.db`);
process.env.DB_PATH = DB_PATH;
process.env.JWT_SECRET = 'test-secret';
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
process.env.NODE_ENV = 'test';

const request = require('supertest');
const { initDB, closeDB, getDB } = require('../src/db/database');
const app = require('../src/app');
const { cleanupOldStaffLocations } = require('../src/services/pdfScheduler');

beforeAll(async () => { await initDB(); });
afterAll(() => {
  closeDB();
  for (const s of ['', '-wal', '-shm']) { try { fs.unlinkSync(DB_PATH + s); } catch (_) {} }
});

async function loginAdmin() {
  const res = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}

describe('orders.js: sin N+1 en el historial', () => {
  test('pedidos con items propios cada uno, sin mezclar items entre pedidos', async () => {
    const token = await loginAdmin();
    const db = getDB();
    const customer = db.prepare(`INSERT INTO customers (phone, name) VALUES ('573005550001','Cliente A')`).run();
    const o1 = db.prepare(`INSERT INTO orders (customer_id, product_name, status, requested_at) VALUES (?, 'Prod A', 'entregado', datetime('now','localtime'))`).run(customer.lastInsertRowid);
    const o2 = db.prepare(`INSERT INTO orders (customer_id, product_name, status, requested_at) VALUES (?, 'Prod B', 'entregado', datetime('now','localtime'))`).run(customer.lastInsertRowid);
    db.prepare(`INSERT INTO order_items (order_id, product_name, quantity) VALUES (?, 'Prod A', 1)`).run(o1.lastInsertRowid);
    db.prepare(`INSERT INTO order_items (order_id, product_name, quantity) VALUES (?, 'Prod B', 2)`).run(o2.lastInsertRowid);

    const res = await request(app).get('/api/orders/history?days=1').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const order1 = res.body.find(o => o.id === o1.lastInsertRowid);
    const order2 = res.body.find(o => o.id === o2.lastInsertRowid);
    expect(order1.items.length).toBe(1);
    expect(order1.items[0].product_name).toBe('Prod A');
    expect(order2.items.length).toBe(1);
    expect(order2.items[0].product_name).toBe('Prod B');
  });

  test('historial vacio no rompe (0 pedidos)', async () => {
    const token = await loginAdmin();
    const res = await request(app).get('/api/orders/history?days=1').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
  });
});

describe('retencion de staff_locations', () => {
  test('borra reportes viejos, conserva los recientes', () => {
    const db = getDB();
    const worker = db.prepare(`INSERT INTO users (username, password_hash, pin, display_name, role) VALUES ('worker_reten','x','x','W','worker')`).run();
    db.prepare(`INSERT INTO staff_locations (user_id, lat, lng, recorded_at) VALUES (?, 4.6, -74.0, datetime('now','-60 days'))`).run(worker.lastInsertRowid);
    db.prepare(`INSERT INTO staff_locations (user_id, lat, lng, recorded_at) VALUES (?, 4.6, -74.0, datetime('now','localtime'))`).run(worker.lastInsertRowid);

    cleanupOldStaffLocations();

    const remaining = db.prepare(`SELECT COUNT(*) c FROM staff_locations WHERE user_id=?`).get(worker.lastInsertRowid);
    expect(remaining.c).toBe(1);
  });
});
