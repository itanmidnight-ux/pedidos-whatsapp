'use strict';
const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('order-notify');
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

async function lastOutboundFor(db, phone) {
  const { rows } = await db.query(`
    SELECT * FROM messages WHERE phone=$1 AND direction='outbound' AND type='order_status'
    ORDER BY id DESC LIMIT 1
  `, [phone]);
  return rows[0];
}

describe('notificaciones de estado de pedido al cliente', () => {
  let token, db, phone, orderId;

  beforeAll(async () => {
    token = await loginAdmin();
    db = getDB();
    phone = '573009990001';
    const { rows: custRows } = await db.query(`INSERT INTO customers (phone, name) VALUES ($1, 'Cliente Notif') RETURNING id`, [phone]);
    const { rows: orderRows } = await db.query(`
      INSERT INTO orders (customer_id, product_name, status, requested_at)
      VALUES ($1, 'Prod Notif', 'pending', now_iso()) RETURNING id
    `, [custRows[0].id]);
    orderId = orderRows[0].id;
  });

  test('en_camino encola mensaje al cliente', async () => {
    const res = await request(app).put(`/api/orders/${orderId}/en_camino`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const msg = await lastOutboundFor(db, phone);
    expect(msg).toBeTruthy();
    expect(msg.content).toMatch(/en camino/i);
    expect(msg.sent).toBe(0);
  });

  test('deliver encola mensaje al cliente', async () => {
    const res = await request(app).put(`/api/orders/${orderId}/deliver`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const msg = await lastOutboundFor(db, phone);
    expect(msg.content).toMatch(/entregado/i);
  });

  test('cancel encola mensaje con motivo', async () => {
    const { rows: cust2Rows } = await db.query(`INSERT INTO customers (phone, name) VALUES ('573009990002','Cliente Cancel') RETURNING id`);
    const { rows: o2Rows } = await db.query(`
      INSERT INTO orders (customer_id, product_name, status, requested_at)
      VALUES ($1, 'Prod Cancel', 'pending', now_iso()) RETURNING id
    `, [cust2Rows[0].id]);

    const res = await request(app)
      .put(`/api/orders/${o2Rows[0].id}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'sin stock' });
    expect(res.status).toBe(200);
    const msg = await lastOutboundFor(db, '573009990002');
    expect(msg.content).toMatch(/cancelado/i);
    expect(msg.content).toMatch(/sin stock/i);
  });
});
