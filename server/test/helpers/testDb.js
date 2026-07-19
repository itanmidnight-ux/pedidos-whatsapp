'use strict';
// Helper compartido para tests -- cada archivo de test corre en su propio
// schema de Postgres (aislamiento equivalente al "1 archivo SQLite temporal
// por test" de la era anterior), sin pisarse entre si y sin necesitar una
// base de datos ni permisos de superusuario aparte -- CREATE SCHEMA alcanza
// con los permisos que ya tiene el rol dueño de la base (ver
// deploy-linux.sh install_postgresql).
//
// Uso (reemplaza el bloque viejo de `DB_PATH = tmp file` al inicio de cada
// test):
//   const { setupTestEnv, teardownTestSchema } = require('./helpers/testDb');
//   setupTestEnv('nombre-del-test');
//   ...
//   beforeAll(async () => { await initDB(); });
//   afterAll(async () => { await teardownTestSchema(); });

function uniqueSchemaName(prefix) {
  const safePrefix = String(prefix || 'test').replace(/[^a-zA-Z0-9_]/g, '_').toLowerCase();
  return `test_${safePrefix}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

// Fija las env vars que necesita database.js -- respeta cualquier valor ya
// definido (ej. exportado a mano contra un Postgres real) y solo rellena
// defaults razonables para correr localmente.
function setupTestEnv(prefix) {
  process.env.NODE_ENV    = 'test';
  process.env.PG_HOST     = process.env.PG_HOST     || '127.0.0.1';
  process.env.PG_PORT     = process.env.PG_PORT     || '5432';
  process.env.PG_DATABASE = process.env.PG_DATABASE || 'supermercado';
  process.env.PG_USER     = process.env.PG_USER     || 'pedidosbot';
  process.env.PG_PASSWORD = process.env.PG_PASSWORD || 'pedidosbot';
  process.env.JWT_SECRET  = process.env.JWT_SECRET  || 'test-secret';
  process.env.API_KEY     = process.env.API_KEY     || 'test-api-key';
  process.env.PG_SCHEMA   = uniqueSchemaName(prefix);
  return process.env.PG_SCHEMA;
}

async function teardownTestSchema() {
  const { getDB, closeDB } = require('../../src/db/database');
  const schema = process.env.PG_SCHEMA;
  try {
    if (schema) await getDB().query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
  } catch (_) { /* pool ya pudo haberse cerrado -- no es fatal para el test */ }
  await closeDB();
}

module.exports = { setupTestEnv, teardownTestSchema, uniqueSchemaName };
