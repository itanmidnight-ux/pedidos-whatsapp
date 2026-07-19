'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('report-categories');
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
process.env.REPORTS_DIR = path.join(os.tmpdir(), `reports-cat-test-${Date.now()}`);

const request = require('supertest');
const ExcelJS = require('exceljs');
const { initDB, getDB } = require('../src/db/database');
const app = require('../src/app');

beforeAll(async () => {
  await initDB();
  const db = getDB();
  const { rows: custRows } = await db.query(`INSERT INTO customers (phone, name, created_at) VALUES ('573001112233','Cliente Test', now_iso()) RETURNING id`);
  const { rows: orderRows } = await db.query(`INSERT INTO orders (customer_id, product_name, product_price, status, requested_at, delivered_at)
              VALUES ($1, 'Bulto 40kg', 50000, 'entregado', now_iso(), now_iso()) RETURNING id`, [custRows[0].id]);
  await db.query(`INSERT INTO order_items (order_id, product_name, product_price, quantity) VALUES ($1, 'Bulto 40kg', 50000, 1)`, [orderRows[0].id]);
});
afterAll(async () => {
  await teardownTestSchema();
});

async function loginAdmin() {
  const res = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}

function todayRange() {
  const t = new Date().toISOString().split('T')[0];
  return { from: t, to: t };
}

test('rechaza categories vacio o invalido', async () => {
  const token = await loginAdmin();
  const { from, to } = todayRange();
  const empty = await request(app).post('/api/reports/export-range').set('Authorization', `Bearer ${token}`).send({ from, to, categories: [] });
  expect(empty.status).toBe(400);
  const invalid = await request(app).post('/api/reports/export-range').set('Authorization', `Bearer ${token}`).send({ from, to, categories: ['inventario'] });
  expect(invalid.status).toBe(400);
});

test('PDF de categoria "resumen" no contiene texto de chats', async () => {
  const token = await loginAdmin();
  const { from, to } = todayRange();
  const res = await request(app).post('/api/reports/export-range').set('Authorization', `Bearer ${token}`)
    .send({ from, to, categories: ['resumen'] });
  expect(res.status).toBe(200);
  expect(res.body.success).toBe(true);
  const pdfText = fs.readFileSync(res.body.filepath, 'latin1');
  expect(pdfText).not.toMatch(/CHAT \(/);
});

test('Excel con categoria "clientes" trae solo la hoja Clientes', async () => {
  const token = await loginAdmin();
  const { from, to } = todayRange();
  const res = await request(app).post('/api/reports/export-range-excel').set('Authorization', `Bearer ${token}`)
    .send({ from, to, categories: ['clientes'] });
  expect(res.status).toBe(200);
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(res.body.filepath);
  expect(wb.getWorksheet('Clientes')).toBeTruthy();
  expect(wb.getWorksheet('Pedidos')).toBeFalsy();
  expect(wb.getWorksheet('Ventas por día')).toBeFalsy();
});

test('Excel con multiples categorias trae una hoja por cada una', async () => {
  const token = await loginAdmin();
  const { from, to } = todayRange();
  const res = await request(app).post('/api/reports/export-range-excel').set('Authorization', `Bearer ${token}`)
    .send({ from, to, categories: ['resumen', 'ventas_dia', 'ventas_producto', 'empleados', 'clientes'] });
  expect(res.status).toBe(200);
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(res.body.filepath);
  for (const name of ['Resumen', 'Ventas por día', 'Ventas por producto', 'Empleados', 'Clientes']) {
    expect(wb.getWorksheet(name)).toBeTruthy();
  }
});

test('GET /api/reports/categories devuelve las 5 categorias reales', async () => {
  const token = await loginAdmin();
  const res = await request(app).get('/api/reports/categories').set('Authorization', `Bearer ${token}`);
  expect(res.status).toBe(200);
  expect(res.body.categories).toEqual(['resumen', 'ventas_dia', 'ventas_producto', 'empleados', 'clientes']);
});
