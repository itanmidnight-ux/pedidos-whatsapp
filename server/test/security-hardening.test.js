'use strict';
const path = require('path');
const os = require('os');
const fs = require('fs');

const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
setupTestEnv('security-hardening');
process.env.SEED_PASSWORD_JESUS = 'admin-test-pw';
// dotenv (cargado por app.js) no sobreescribe vars ya seteadas -- fijamos
// esta ANTES del primer require de app.js para no escribir reportes en el
// REPORTS_DIR real de produccion (sin permisos para este usuario/test).
process.env.REPORTS_DIR = path.join(os.tmpdir(), `reports-test-${Date.now()}`);

const request = require('supertest');
const ExcelJS = require('exceljs');
const { initDB, getDB } = require('../src/db/database');
const app = require('../src/app');
const { getIP } = require('../src/utils/ip');
const { flushIpActivity } = require('../src/middleware/ipActivity');
const { raiseAlert } = require('../src/utils/securityAlert');
const { scanSuspiciousIPs } = require('../src/services/securityMonitor');

beforeAll(async () => { await initDB(); });
afterAll(async () => { await teardownTestSchema(); });

async function loginAdmin() {
  const res = await request(app).post('/api/auth/token').send({ username: 'jesus', password: 'admin-test-pw' });
  return res.body.token;
}
function normPhone(phone) { return '57' + phone; }
async function registerClient(phone, label) {
  return request(app).post('/api/auth/register').send({
    phone, password: 'password123', display_name: 'Cliente Test',
    email: `${label}@example.com`, address: 'Calle de prueba 123',
  });
}

describe('getIP', () => {
  test('usa x-forwarded-for cuando existe', () => {
    const req = { headers: { 'x-forwarded-for': '203.0.113.5, 10.0.0.1' }, socket: { remoteAddress: '10.0.0.1' } };
    expect(getIP(req)).toBe('203.0.113.5');
  });
  test('cae a socket.remoteAddress si no hay x-forwarded-for', () => {
    const req = { headers: {}, socket: { remoteAddress: '192.168.1.10' } };
    expect(getIP(req)).toBe('192.168.1.10');
  });
});

describe('Fuerza bruta: bloqueo por cuenta, no por IP', () => {
  test('5 fallos bloquean la cuenta aunque el atacante rote de IP', async () => {
    await registerClient('3001110077', 'cliente_bruteforce');
    const user = normPhone('3001110077');
    for (let i = 0; i < 4; i++) {
      await request(app).post('/api/auth/token').set('X-Forwarded-For', '203.0.113.10')
        .send({ username: user, password: 'incorrecta' });
    }
    const fifth = await request(app).post('/api/auth/token').set('X-Forwarded-For', '198.51.100.20')
      .send({ username: user, password: 'incorrecta' });
    expect(fifth.status).toBe(401);
    const sixth = await request(app).post('/api/auth/token').set('X-Forwarded-For', '192.0.2.30')
      .send({ username: user, password: 'password123' });
    expect(sixth.status).toBe(429);
    expect(sixth.body.retry_in).toBeGreaterThan(0);
  });
});

describe('Anti-XSS en productos y mensajes', () => {
  test('nombre de producto con <script> queda limpio al crear y editar', async () => {
    const token = await loginAdmin();
    const created = await request(app).post('/api/products').set('Authorization', `Bearer ${token}`)
      .send({ name: '<script>alert(1)</script>Concentrado Perro', price: 50000 });
    expect(created.body.name).not.toContain('<script>');
    expect(created.body.name).toContain('Concentrado Perro');

    const edited = await request(app).put(`/api/products/${created.body.id}`).set('Authorization', `Bearer ${token}`)
      .send({ name: '<img src=x onerror=alert(1)>Editado' });
    expect(edited.body.name).not.toContain('<img');
    expect(edited.body.name).toContain('Editado');
  });

  test('mensaje directo con tags queda limpio', async () => {
    const token = await loginAdmin();
    await request(app).post('/api/messages/send').set('Authorization', `Bearer ${token}`)
      .send({ phone: '573000000001', content: '<script>x</script>Hola cliente' });
    const list = await request(app).get('/api/messages/573000000001').set('Authorization', `Bearer ${token}`);
    const saved = list.body.find(m => m.direction === 'outbound');
    expect(saved.content).not.toContain('<script>');
  });
});

describe('Anti-escalamiento de privilegios (regresión)', () => {
  test('cliente no puede auto-asignarse rol vía PUT /api/users/me', async () => {
    await registerClient('3001110088', 'cliente_escalamiento');
    const login = await request(app).post('/api/auth/token').send({ username: normPhone('3001110088'), password: 'password123' });
    await request(app).put('/api/users/me').set('Authorization', `Bearer ${login.body.token}`)
      .send({ role: 'admin', display_name: 'Intento de escalamiento' });
    const adminToken = await loginAdmin();
    const list = await request(app).get('/api/users').set('Authorization', `Bearer ${adminToken}`);
    const user = list.body.users.find(u => u.username === normPhone('3001110088'));
    expect(user.role).toBe('client');
  });

  test('worker no puede modificar la cuenta de otro usuario', async () => {
    const adminToken = await loginAdmin();
    await request(app).post('/api/users').set('Authorization', `Bearer ${adminToken}`).send({ username: 'worker_a', password: 'password123', role: 'worker' });
    await request(app).post('/api/users').set('Authorization', `Bearer ${adminToken}`).send({ username: 'worker_b', password: 'password123', role: 'worker' });
    const idOfB = (await request(app).get('/api/users').set('Authorization', `Bearer ${adminToken}`)).body.users.find(u => u.username === 'worker_b').id;
    const loginA = await request(app).post('/api/auth/token').send({ username: 'worker_a', password: 'password123' });
    const res = await request(app).put(`/api/users/${idOfB}`).set('Authorization', `Bearer ${loginA.body.token}`).send({ role: 'admin' });
    expect(res.status).toBe(403);
  });
});

describe('Logs no filtran credenciales', () => {
  test('una request con Authorization no expone el token en el ring buffer', async () => {
    await request(app).get('/api/orders').set('Authorization', 'Bearer token-de-prueba-xyz');
    const logger = require('../src/utils/logger');
    const logs = JSON.stringify(logger.getRecentLogs());
    expect(logs).not.toContain('token-de-prueba-xyz');
  });
});

describe('anti formula-injection en export Excel', () => {
  test('nombre de cliente que empieza con "=" no queda como fórmula ejecutable', async () => {
    const db = getDB();
    const { rows: custRows } = await db.query(`INSERT INTO customers (phone, name) VALUES ($1, $2) RETURNING id`, ['573009998877', "=cmd|'/c calc'!A1"]);
    await db.query(`INSERT INTO orders (customer_id, product_name, product_price, status, requested_at)
                VALUES ($1, 'Producto test', 20000, 'entregado', now_iso())`, [custRows[0].id]);
    const { generateRangeReportXLSX } = require('../src/services/excelGenerator');
    // toISOString() da la fecha en UTC -- de noche en Colombia (UTC-5) ya es
    // "manana" en UTC, y el filtro de rango quedaba desalineado. en-CA
    // formatea como YYYY-MM-DD directo, en la zona horaria real del negocio.
    const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Bogota' });
    const filepath = await generateRangeReportXLSX(today, today, ['clientes']);
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.readFile(filepath);
    const ws = wb.getWorksheet('Clientes');
    // La hoja se ordena por gastado DESC y la DB del archivo acumula datos de
    // tests anteriores -- buscar la fila por telefono en vez de asumir una
    // posicion fija, para no depender del orden relativo con otras filas.
    let clienteCell = null;
    ws.eachRow((row, rowNumber) => {
      if (rowNumber === 1) return;
      if (row.getCell(2).value === '573009998877') clienteCell = row.getCell(1);
    });
    expect(clienteCell).not.toBeNull();
    expect(clienteCell.value.toString().startsWith('=')).toBe(false);
    expect(clienteCell.value.toString()).toContain('cmd');
    fs.unlinkSync(filepath);
  });
});

describe('tracking de actividad por IP', () => {
  test('requests quedan agregados por IP y minuto tras un flush', async () => {
    await request(app).get('/health').set('X-Forwarded-For', '203.0.113.199');
    await request(app).get('/health').set('X-Forwarded-For', '203.0.113.199');
    await request(app).get('/api/orders').set('X-Forwarded-For', '203.0.113.199');
    await flushIpActivity();
    const { rows } = await getDB().query('SELECT * FROM ip_activity WHERE ip = $1', ['203.0.113.199']);
    expect(rows.length).toBe(1);
    expect(rows[0].requests).toBe(3);
    expect(rows[0].count_401).toBe(1);
  });

  test('un 401 generico (token expirado en ruta protegida) NO cuenta como login fallido', async () => {
    // GET /api/orders sin token -- 401 generico, no es un intento de login.
    await request(app).get('/api/orders').set('X-Forwarded-For', '203.0.113.222');
    await flushIpActivity();
    const { rows } = await getDB().query('SELECT * FROM ip_activity WHERE ip = $1', ['203.0.113.222']);
    expect(rows[0].count_401).toBe(1);
    expect(rows[0].count_auth_fail).toBe(0);
  });

  test('un login fallido real en /api/auth/token SI cuenta como login fallido', async () => {
    await request(app).post('/api/auth/token').set('X-Forwarded-For', '203.0.113.223')
      .send({ username: 'no-existe', password: 'x' });
    await flushIpActivity();
    const { rows } = await getDB().query('SELECT * FROM ip_activity WHERE ip = $1', ['203.0.113.223']);
    expect(rows[0].count_auth_fail).toBe(1);
  });
});

describe('raiseAlert', () => {
  test('inserta en security_alerts y encola WhatsApp al admin', async () => {
    const db = getDB();
    await db.query(`UPDATE users SET phone = '573001112233' WHERE role = 'admin'`);
    await raiseAlert('brute_force', 'Cuenta 573009998877 bloqueada por fuerza bruta');
    const { rows: alertRows } = await db.query('SELECT * FROM security_alerts ORDER BY id DESC LIMIT 1');
    expect(alertRows[0].kind).toBe('brute_force');
    const { rows: outboundRows } = await db.query(`SELECT * FROM messages WHERE phone = '573001112233' AND direction='outbound' ORDER BY id DESC LIMIT 1`);
    expect(outboundRows[0].content).toContain('fuerza bruta');
  });
});

describe('scanSuspiciousIPs', () => {
  test('marca alerta cuando una IP supera el umbral de LOGINS fallidos reales', async () => {
    const db = getDB();
    const minute = new Date().toISOString().slice(0, 16);
    await db.query(`INSERT INTO ip_activity (ip, minute, requests, count_401, count_403, count_404, count_auth_fail) VALUES ('198.51.100.77', $1, 20, 6, 0, 0, 6)`, [minute]);
    await scanSuspiciousIPs();
    const { rows } = await db.query(`SELECT * FROM security_alerts WHERE kind='ip_flagged' ORDER BY id DESC LIMIT 1`);
    expect(rows[0].message).toContain('198.51.100.77');
  });

  test('NO marca alerta por 401/403 genericos sin logins fallidos reales (evita falsos positivos)', async () => {
    const db = getDB();
    const minute = new Date().toISOString().slice(0, 16);
    // Mismo volumen de 401/403 que antes disparaba alerta -- ahora, sin
    // count_auth_fail, es trafico normal (tokens expirando, recursos
    // opcionales sin encontrar), no debe generar ninguna alerta nueva.
    await db.query(`INSERT INTO ip_activity (ip, minute, requests, count_401, count_403, count_404, count_auth_fail) VALUES ('198.51.100.88', $1, 20, 6, 0, 0, 0)`, [minute]);
    const { rows: beforeRows } = await db.query(`SELECT COUNT(*) c FROM security_alerts WHERE kind='ip_flagged' AND message LIKE '%198.51.100.88%'`);
    await scanSuspiciousIPs();
    const { rows: afterRows } = await db.query(`SELECT COUNT(*) c FROM security_alerts WHERE kind='ip_flagged' AND message LIKE '%198.51.100.88%'`);
    expect(Number(afterRows[0].c)).toBe(Number(beforeRows[0].c));
  });

  test('nunca marca localhost (webhook interno del bot) como sospechoso', async () => {
    const db = getDB();
    const minute = new Date().toISOString().slice(0, 16);
    await db.query(`INSERT INTO ip_activity (ip, minute, requests, count_401, count_403, count_404, count_auth_fail) VALUES ('127.0.0.1', $1, 1000, 50, 50, 50, 50)`, [minute]);
    await scanSuspiciousIPs();
    const { rows } = await db.query(`SELECT COUNT(*) c FROM security_alerts WHERE kind='ip_flagged' AND message LIKE '%127.0.0.1%'`);
    expect(Number(rows[0].c)).toBe(0);
  });
});
