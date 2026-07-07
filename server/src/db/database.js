const Database  = require('better-sqlite3');
const bcrypt    = require('bcrypt');
const crypto    = require('crypto');
const path      = require('path');
const fs        = require('fs');
const logger    = require('../utils/logger');
const { runMigrations } = require('./migrations');

const DB_PATH    = process.env.DB_PATH || path.join(__dirname, '../../pedidos.db');
const SALT_ROUNDS = 10;

const SEED_USERS = [
  { username: 'jesus',  display_name: 'Jesús',  role: 'admin'  },
  { username: 'johana', display_name: 'Johana', role: 'worker' },
  { username: 'felipe', display_name: 'Felipe', role: 'worker' },
  { username: 'fabian', display_name: 'Fabián', role: 'worker' },
];

// Password de arranque para cuentas seed: viene de env (SEED_PASSWORD_<USUARIO>),
// o se genera al azar y se imprime una sola vez — salvo 'jesus', cuyo default
// pedido explicitamente es el mismo username (cambiarla tras el primer login).
function seedPassword(username) {
  const envVar = `SEED_PASSWORD_${username.toUpperCase()}`;
  if (process.env[envVar]) return process.env[envVar];
  if (username === 'jesus') {
    logger.warn(`[seed] ${envVar} no definida — usando password por defecto "jesus" (cámbiala tras el primer login)`);
    return 'jesus';
  }
  const generated = crypto.randomBytes(9).toString('base64url');
  logger.warn(`[seed] ${envVar} no definida — password generada para "${username}": ${generated} (cámbiala tras el primer login)`);
  return generated;
}

let db;

async function initDB() {
  db = new Database(DB_PATH);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  db.exec(schema);
  runMigrations(db);

  // Seed users — insert if missing, update display_name + role if changed
  for (const u of SEED_USERS) {
    const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(u.username);
    if (!existing) {
      const password = seedPassword(u.username);
      const hash = await bcrypt.hash(password, SALT_ROUNDS);
      const pin  = await bcrypt.hash(password, SALT_ROUNDS);
      db.prepare(
        'INSERT OR IGNORE INTO users (username, password_hash, pin, display_name, role) VALUES (?,?,?,?,?)'
      ).run(u.username, hash, pin, u.display_name, u.role);
    } else {
      db.prepare('UPDATE users SET role=?, display_name=? WHERE username=?')
        .run(u.role, u.display_name, u.username);
    }
  }

  // Default settings
  db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('nequi_phone', '3001234567')`).run();
  db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('nequi_name', 'Concentrados Monserrath')`).run();
  db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('empresa_nombre', 'Concentrados Monserrath')`).run();
  db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('empresa_descripcion', 'Distribuidora de concentrados y alimentos para animales')`).run();
  db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('horario_atencion', 'Lunes a Sábado 8:00am - 6:00pm')`).run();
  db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('theme_primary', '#2D5016')`).run();
  db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('theme_accent', '#D4800A')`).run();
  db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('theme_name', 'Concentrados Monserrath')`).run();
  db.prepare(`INSERT OR IGNORE INTO settings (key, value) VALUES ('theme_logo_url', '')`).run();

  logger.info({ path: DB_PATH }, 'DB inicializada');
}

function getDB() {
  if (!db) throw new Error('DB no inicializada. Llama initDB() primero.');
  return db;
}

function closeDB() {
  if (db) { db.close(); db = null; }
}

module.exports = { initDB, getDB, closeDB };
