'use strict';
const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('perf-fixes-2');
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';

const request = require('supertest');
const { initDB, getDB } = require('../src/db/database');
const app = require('../src/app');
const { cleanupOldStaffLocations } = require('../src/services/pdfScheduler');

beforeAll(async () => { await initDB(); });
afterAll(async () => { await teardownTestSchema(); });

async function loginAdmin() {
  const res = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}

describe('orders.js: sin N+1 en el historial', () => {
  test('pedidos con items propios cada uno, sin mezclar items entre pedidos', async () => {
    const token = await loginAdmin();
    const db = getDB();
    const { rows: custRows } = await db.query(`INSERT INTO customers (phone, name) VALUES ('573005550001','Cliente A') RETURNING id`);
    const custId = custRows[0].id;
    const { rows: o1Rows } = await db.query(`INSERT INTO orders (customer_id, product_name, status, requested_at) VALUES ($1, 'Prod A', 'entregado', now_iso()) RETURNING id`, [custId]);
    const { rows: o2Rows } = await db.query(`INSERT INTO orders (customer_id, product_name, status, requested_at) VALUES ($1, 'Prod B', 'entregado', now_iso()) RETURNING id`, [custId]);
    const o1Id = o1Rows[0].id, o2Id = o2Rows[0].id;
    await db.query(`INSERT INTO order_items (order_id, product_name, quantity) VALUES ($1, 'Prod A', 1)`, [o1Id]);
    await db.query(`INSERT INTO order_items (order_id, product_name, quantity) VALUES ($1, 'Prod B', 2)`, [o2Id]);

    const res = await request(app).get('/api/orders/history?days=1').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const order1 = res.body.find(o => o.id === o1Id);
    const order2 = res.body.find(o => o.id === o2Id);
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
  test('borra reportes viejos, conserva los recientes', async () => {
    const db = getDB();
    const { rows: workerRows } = await db.query(
      `INSERT INTO users (username, password_hash, pin, display_name, role) VALUES ('worker_reten','x','x','W','worker') RETURNING id`
    );
    const workerId = workerRows[0].id;
    await db.query(`INSERT INTO staff_locations (user_id, lat, lng, recorded_at)
      VALUES ($1, 4.6, -74.0, to_char((now() AT TIME ZONE 'UTC') - INTERVAL '60 days', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))`, [workerId]);
    await db.query(`INSERT INTO staff_locations (user_id, lat, lng, recorded_at) VALUES ($1, 4.6, -74.0, now_iso())`, [workerId]);

    await cleanupOldStaffLocations();

    const { rows: remainingRows } = await db.query(`SELECT COUNT(*) c FROM staff_locations WHERE user_id=$1`, [workerId]);
    expect(Number(remainingRows[0].c)).toBe(1);
  });
});
