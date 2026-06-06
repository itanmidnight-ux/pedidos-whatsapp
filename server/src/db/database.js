const Database  = require('better-sqlite3');
const bcrypt    = require('bcrypt');
const path      = require('path');
const fs        = require('fs');

const DB_PATH    = path.join(__dirname, '../../pedidos.db');
const SALT_ROUNDS = 10;

const SEED_USERS = [
  { username: 'jesus',  display_name: 'Jesús',  password: '1234', role: 'admin'  },
  { username: 'johana', display_name: 'Johana', password: '1234', role: 'worker' },
  { username: 'felipe', display_name: 'Felipe', password: '1234', role: 'worker' },
  { username: 'fabian', display_name: 'Fabián', password: '1234', role: 'worker' },
];

let db;

async function initDB() {
  db = new Database(DB_PATH);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  db.exec(schema);

  // Safe migrations — silently ignored if column/table already exists
  const migrations = [
    'ALTER TABLE messages      ADD COLUMN flagged       INTEGER DEFAULT 0',
    'ALTER TABLE messages      ADD COLUMN flag_reason   TEXT',
    'ALTER TABLE users         ADD COLUMN pin           TEXT',
    'ALTER TABLE users         ADD COLUMN display_name  TEXT',
    'ALTER TABLE orders        ADD COLUMN claimed_by    INTEGER',
    'ALTER TABLE orders        ADD COLUMN claimed_at    TEXT',
    'ALTER TABLE orders        ADD COLUMN cancel_reason TEXT',
    'ALTER TABLE pending_orders ADD COLUMN pending_items TEXT DEFAULT \'[]\'',
    `CREATE TABLE IF NOT EXISTS order_items (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
       product_id INTEGER, product_name TEXT NOT NULL,
       product_price REAL, quantity INTEGER DEFAULT 1
     )`,
    'CREATE INDEX IF NOT EXISTS idx_orders_status     ON orders(status)',
    'CREATE INDEX IF NOT EXISTS idx_orders_claimed_by ON orders(claimed_by)',
    'CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id)',
    // Ensure jesus is admin
    "UPDATE users SET role='admin' WHERE username='jesus'",
    // NLP.js migration: message type column + promotional campaigns
    "ALTER TABLE messages ADD COLUMN type TEXT DEFAULT 'direct'",
    `CREATE TABLE IF NOT EXISTS promotional_campaigns (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       message TEXT NOT NULL,
       target_type TEXT DEFAULT 'all',
       sent_count INTEGER DEFAULT 0,
       created_by INTEGER REFERENCES users(id),
       created_at TEXT DEFAULT (datetime('now','localtime'))
     )`,
  ];
  for (const sql of migrations) {
    try { db.exec(sql); } catch { /* already exists */ }
  }

  // Seed users — insert if missing, update display_name + role if changed
  for (const u of SEED_USERS) {
    const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(u.username);
    if (!existing) {
      const hash = await bcrypt.hash(u.password, SALT_ROUNDS);
      const pin  = await bcrypt.hash(u.password, SALT_ROUNDS);
      db.prepare(
        'INSERT OR IGNORE INTO users (username, password_hash, pin, display_name, role) VALUES (?,?,?,?,?)'
      ).run(u.username, hash, pin, u.display_name, u.role);
    } else {
      db.prepare('UPDATE users SET role=?, display_name=? WHERE username=?')
        .run(u.role, u.display_name, u.username);
    }
  }

  console.log('DB inicializada en', DB_PATH);
}

function getDB() {
  if (!db) throw new Error('DB no inicializada. Llama initDB() primero.');
  return db;
}

module.exports = { initDB, getDB };
