'use strict';
const { Pool } = require('pg');

// Pool propio, separado del server principal (proceso Node distinto) --
// solo se usan queries SELECT en todo public-site/queries.js por
// convencion (el sitio publico nunca escribe). Mismas credenciales que el
// server principal (mismo .env via EnvironmentFile en systemd).
function connectionConfig() {
  if (process.env.DATABASE_URL) return { connectionString: process.env.DATABASE_URL };
  return {
    host:     process.env.PG_HOST     || '127.0.0.1',
    port:     Number(process.env.PG_PORT || 5432),
    database: process.env.PG_DATABASE || 'supermercado',
    user:     process.env.PG_USER     || 'pedidosbot',
    password: process.env.PG_PASSWORD,
  };
}

let pool;
function getPool() {
  if (!pool) pool = new Pool({ ...connectionConfig(), max: Number(process.env.PG_POOL_MAX_SITE || 5) });
  return pool;
}

module.exports = { getPool };
