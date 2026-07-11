'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

const DB_PATH = path.join(os.tmpdir(), `order-notify-${Date.now()}-${Math.random().toString(36).slice(2)}.db`);
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

async function loginAdmin() {
  const res = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}

function lastOutboundFor(db, phone) {
  return db.prepare(`
    SELECT * FROM messages WHERE phone=? AND direction='outbound' AND type='order_status'
    ORDER BY id DESC LIMIT 1
  `).get(phone);
}

describe('notificaciones de estado de pedido al cliente', () => {
  let token, db, phone, orderId;

  beforeAll(async () => {
    token = await loginAdmin();
    db = getDB();
    phone = '573009990001';
    const customer = db.prepare(`INSERT INTO customers (phone, name) VALUES (?, 'Cliente Notif')`).run(phone);
    const o = db.prepare(`
      INSERT INTO orders (customer_id, product_name, status, requested_at)
      VALUES (?, 'Prod Notif', 'pending', datetime('now','localtime'))
    `).run(customer.lastInsertRowid);
    orderId = o.lastInsertRowid;
  });

  test('en_camino encola mensaje al cliente', async () => {
    const res = await request(app).put(`/api/orders/${orderId}/en_camino`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const msg = lastOutboundFor(db, phone);
    expect(msg).toBeTruthy();
    expect(msg.content).toMatch(/en camino/i);
    expect(msg.sent).toBe(0);
  });

  test('deliver encola mensaje al cliente', async () => {
    const res = await request(app).put(`/api/orders/${orderId}/deliver`).set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    const msg = lastOutboundFor(db, phone);
    expect(msg.content).toMatch(/entregado/i);
  });

  test('cancel encola mensaje con motivo', async () => {
    const customer2 = db.prepare(`INSERT INTO customers (phone, name) VALUES ('573009990002','Cliente Cancel')`).run();
    const o2 = db.prepare(`
      INSERT INTO orders (customer_id, product_name, status, requested_at)
      VALUES (?, 'Prod Cancel', 'pending', datetime('now','localtime'))
    `).run(customer2.lastInsertRowid);

    const res = await request(app)
      .put(`/api/orders/${o2.lastInsertRowid}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'sin stock' });
    expect(res.status).toBe(200);
    const msg = lastOutboundFor(db, '573009990002');
    expect(msg.content).toMatch(/cancelado/i);
    expect(msg.content).toMatch(/sin stock/i);
  });
});
