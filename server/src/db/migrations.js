'use strict';
const logger = require('../utils/logger');

// El historial de 65 migraciones de la era SQLite se consolido directo en
// schema.sql al pasar a PostgreSQL (una instalacion Postgres siempre
// arranca vacia, no hay upgrades in-place que preservar). Este archivo
// queda vacio y listo para futuras migraciones *nuevas*, ya en dialecto
// Postgres -- mismo patron de siempre: cada entrada corre una sola vez,
// se registra en schema_migrations apenas se aplica con exito.
const MIGRATIONS = [
];

async function runMigrations(pool) {
  await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    name TEXT PRIMARY KEY,
    applied_at TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
  )`);

  const { rows } = await pool.query('SELECT name FROM schema_migrations');
  const applied = new Set(rows.map(r => r.name));

  for (const m of MIGRATIONS) {
    if (applied.has(m.name)) continue;
    try {
      await pool.query(m.sql);
      await pool.query('INSERT INTO schema_migrations (name) VALUES ($1) ON CONFLICT DO NOTHING', [m.name]);
    } catch (e) {
      // Mismo criterio que en la era SQLite: si ya existe (reintento tras un
      // deploy parcial), se marca aplicada; cualquier otro error se reporta
      // y se reintenta en el proximo arranque.
      const benign = /already exists/i.test(e.message);
      if (benign) {
        await pool.query('INSERT INTO schema_migrations (name) VALUES ($1) ON CONFLICT DO NOTHING', [m.name]);
      } else {
        logger.error({ err: e.message, migration: m.name }, 'Migración falló — se reintentará en el próximo arranque');
      }
    }
  }
}

module.exports = { runMigrations, MIGRATIONS };
