'use strict';
const { Pool, Client } = require('pg');
const bcrypt   = require('bcrypt');
const crypto   = require('crypto');
const path     = require('path');
const fs       = require('fs');
const logger   = require('../utils/logger');
const { runMigrations } = require('./migrations');
const { archiveLegacyRows } = require('../services/locationHistory');

const SALT_ROUNDS = 10;

const SEED_USERS = [
  { username: 'jesus',  display_name: 'Jesús',  role: 'admin'  },
  { username: 'johana', display_name: 'Johana', role: 'worker' },
  { username: 'felipe', display_name: 'Felipe', role: 'worker' },
  { username: 'fabian', display_name: 'Fabián', role: 'worker' },
];

// Password de arranque para cuentas seed: viene de env (SEED_PASSWORD_<USUARIO>),
// o se genera al azar y se imprime una sola vez -- NUNCA hay un default
// hardcodeado (ni siquiera para 'jesus'), para no dejar una credencial
// conocida en ninguna instalacion nueva.
function seedPassword(username) {
  const envVar = `SEED_PASSWORD_${username.toUpperCase()}`;
  if (process.env[envVar]) return process.env[envVar];
  const generated = crypto.randomBytes(24).toString('base64url');
  logger.warn(`[seed] ${envVar} no definida — password generada para "${username}": ${generated} (cámbiala tras el primer login)`);
  return generated;
}

function connectionConfig() {
  // PG_SCHEMA: usado SOLO por los tests (ver test/helpers/testDb.js) -- cada
  // archivo de test corre en su propio schema Postgres, aislamiento
  // equivalente al "1 archivo SQLite por test" de la era anterior, sin
  // pisarse entre si ni necesitar una base de datos separada por test.
  const options = process.env.PG_SCHEMA ? { options: `-c search_path=${process.env.PG_SCHEMA}` } : {};
  if (process.env.DATABASE_URL) return { connectionString: process.env.DATABASE_URL, ...options };
  return {
    host:     process.env.PG_HOST     || '127.0.0.1',
    port:     Number(process.env.PG_PORT || 5432),
    database: process.env.PG_DATABASE || 'supermercado',
    user:     process.env.PG_USER     || 'pedidosbot',
    password: process.env.PG_PASSWORD,
    ...options,
  };
}

let pool;

async function initDB() {
  // El schema de test debe existir ANTES de abrir el pool con
  // search_path=ese-schema (si no, cada conexion cae de vuelta a "public"
  // porque Postgres ignora search_path apuntando a un schema inexistente).
  // Va por una conexion aparte, corta, sin search_path fijado.
  if (process.env.PG_SCHEMA) {
    const bootstrapCfg = connectionConfig();
    delete bootstrapCfg.options;
    const bootstrapPool = new Pool({ ...bootstrapCfg, max: 1 });
    await bootstrapPool.query(`CREATE SCHEMA IF NOT EXISTS "${process.env.PG_SCHEMA}"`);
    await bootstrapPool.end();
  }

  pool = new Pool({
    ...connectionConfig(),
    // Tope de conexiones por instancia del server -- con varias instancias
    // (Fase 2, horizontal scaling) cada una abre su propio pool, por eso el
    // tope es conservador y no "todas las conexiones que Postgres aguante".
    max: Number(process.env.PG_POOL_MAX || 10),
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
  });
  pool.on('error', (err) => logger.error({ err: err.message }, '[db] error inesperado en el pool de Postgres'));

  const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  await pool.query(schema);
  await runMigrations(pool);
  await archiveLegacyRows(pool);

  // Seed users — insert if missing, update display_name + role if changed
  for (const u of SEED_USERS) {
    const { rows } = await pool.query('SELECT id FROM users WHERE username = $1', [u.username]);
    if (rows.length === 0) {
      const password = seedPassword(u.username);
      const hash = await bcrypt.hash(password, SALT_ROUNDS);
      const pin  = await bcrypt.hash(password, SALT_ROUNDS);
      await pool.query(
        'INSERT INTO users (username, password_hash, pin, display_name, role) VALUES ($1,$2,$3,$4,$5) ON CONFLICT (username) DO NOTHING',
        [u.username, hash, pin, u.display_name, u.role]
      );
    } else {
      await pool.query('UPDATE users SET role=$1, display_name=$2 WHERE username=$3', [u.role, u.display_name, u.username]);
    }
  }

  // Default settings
  const defaults = [
    ['nequi_phone', '3001234567'],
    ['nequi_name', 'Supermercado GO'],
    ['empresa_nombre', 'Supermercado GO'],
    ['empresa_descripcion', 'Supermercado de barrio en Cúcuta — víveres, aseo y más'],
    ['horario_atencion', 'Lunes a Sábado 8:00am - 8:00pm, Domingos 8:00am - 2:00pm'],
    ['theme_primary', '#2e7d32'],
    ['theme_accent', '#f9a825'],
    ['theme_name', 'Supermercado GO'],
    ['theme_logo_url', ''],
  ];
  for (const [key, value] of defaults) {
    await pool.query('INSERT INTO settings (key, value) VALUES ($1,$2) ON CONFLICT (key) DO NOTHING', [key, value]);
  }

  logger.info({ host: connectionConfig().host || 'DATABASE_URL' }, 'DB (PostgreSQL) inicializada');
}

function getDB() {
  if (!pool) throw new Error('DB no inicializada. Llama initDB() primero.');
  return pool;
}

// Reemplaza el db.transaction(fn) sincrono de better-sqlite3 -- pg necesita
// una sola conexion dedicada (no el pool compartido) para que BEGIN/COMMIT
// envuelvan las mismas queries. fn recibe un "client" con el mismo .query()
// que el pool; siempre se hace ROLLBACK + release si algo falla.
async function withTransaction(fn) {
  const client = await getDB().connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

async function closeDB() {
  if (pool) { await pool.end(); pool = null; }
}

// Cliente dedicado para LISTEN/NOTIFY (waBot.js) -- necesita su propia
// conexion persistente, nunca una del pool (el pool puede reciclar/cerrar
// conexiones en cualquier momento, lo que cortaria la suscripcion sin
// avisar). El caller es responsable de connect()/end() y de reintentar si
// se cae.
function createListenClient() {
  return new Client(connectionConfig());
}

module.exports = { initDB, getDB, closeDB, withTransaction, createListenClient };
