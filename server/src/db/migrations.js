'use strict';
const logger = require('../utils/logger');

// Cada entrada corre una sola vez, para siempre — se registra en
// schema_migrations apenas se aplica con éxito. Nombres estables:
// no renombrar ni reordenar entradas ya desplegadas.
const MIGRATIONS = [
  { name: '001_messages_flagged',       sql: 'ALTER TABLE messages ADD COLUMN flagged INTEGER DEFAULT 0' },
  { name: '002_messages_flag_reason',   sql: 'ALTER TABLE messages ADD COLUMN flag_reason TEXT' },
  { name: '003_users_pin',              sql: 'ALTER TABLE users ADD COLUMN pin TEXT' },
  { name: '004_users_display_name',     sql: 'ALTER TABLE users ADD COLUMN display_name TEXT' },
  { name: '005_orders_claimed_by',      sql: 'ALTER TABLE orders ADD COLUMN claimed_by INTEGER' },
  { name: '006_orders_claimed_at',      sql: 'ALTER TABLE orders ADD COLUMN claimed_at TEXT' },
  { name: '007_orders_cancel_reason',   sql: 'ALTER TABLE orders ADD COLUMN cancel_reason TEXT' },
  { name: '008_pending_orders_items',   sql: "ALTER TABLE pending_orders ADD COLUMN pending_items TEXT DEFAULT '[]'" },
  { name: '009_order_items_table', sql: `
    CREATE TABLE IF NOT EXISTS order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      product_id INTEGER, product_name TEXT NOT NULL,
      product_price REAL, quantity INTEGER DEFAULT 1
    )` },
  { name: '010_idx_orders_status',     sql: 'CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)' },
  { name: '011_idx_orders_claimed_by', sql: 'CREATE INDEX IF NOT EXISTS idx_orders_claimed_by ON orders(claimed_by)' },
  { name: '012_idx_order_items_order', sql: 'CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id)' },
  { name: '013_messages_type',         sql: "ALTER TABLE messages ADD COLUMN type TEXT DEFAULT 'direct'" },
  { name: '014_promotional_campaigns_table', sql: `
    CREATE TABLE IF NOT EXISTS promotional_campaigns (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      message TEXT NOT NULL,
      target_type TEXT DEFAULT 'all',
      sent_count INTEGER DEFAULT 0,
      created_by INTEGER REFERENCES users(id),
      created_at TEXT DEFAULT (datetime('now','localtime'))
    )` },
  { name: '015_messages_media_type',   sql: 'ALTER TABLE messages ADD COLUMN media_type TEXT' },
  { name: '016_messages_media_url',    sql: 'ALTER TABLE messages ADD COLUMN media_url TEXT' },
  { name: '017_customers_profile_pic', sql: 'ALTER TABLE customers ADD COLUMN profile_pic_url TEXT' },
  { name: '018_customers_archived',    sql: 'ALTER TABLE customers ADD COLUMN archived INTEGER DEFAULT 0' },
  { name: '019_product_images_table', sql: `
    CREATE TABLE IF NOT EXISTS product_images (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      filename TEXT NOT NULL,
      created_at DATETIME DEFAULT (datetime('now','localtime')),
      FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
    )` },
  { name: '020_estados_table', sql: `
    CREATE TABLE IF NOT EXISTS estados (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      admin_username TEXT NOT NULL,
      filename TEXT NOT NULL,
      media_type TEXT NOT NULL DEFAULT 'image',
      caption TEXT,
      created_at DATETIME DEFAULT (datetime('now','localtime')),
      expires_at DATETIME NOT NULL
    )` },
  { name: '021_cart_items_table', sql: `
    CREATE TABLE IF NOT EXISTS cart_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_username TEXT NOT NULL,
      product_id INTEGER NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      delivery_date TEXT,
      created_at DATETIME DEFAULT (datetime('now','localtime'))
    )` },
  { name: '022_settings_table', sql: `
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at DATETIME DEFAULT (datetime('now','localtime'))
    )` },
  { name: '023_client_orders_table', sql: `
    CREATE TABLE IF NOT EXISTS client_orders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_username TEXT NOT NULL,
      items_json TEXT NOT NULL,
      total REAL NOT NULL,
      payment_method TEXT NOT NULL,
      nequi_reference TEXT,
      status TEXT DEFAULT 'pending',
      delivery_date TEXT,
      created_at DATETIME DEFAULT (datetime('now','localtime'))
    )` },
  { name: '024_users_address', sql: 'ALTER TABLE users ADD COLUMN address TEXT' },
  { name: '025_estado_reactions_table', sql: `
    CREATE TABLE IF NOT EXISTS estado_reactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      estado_id INTEGER NOT NULL,
      username TEXT NOT NULL,
      created_at DATETIME DEFAULT (datetime('now','localtime')),
      UNIQUE(estado_id, username),
      FOREIGN KEY(estado_id) REFERENCES estados(id) ON DELETE CASCADE
    )` },
  { name: '026_estado_comments_table', sql: `
    CREATE TABLE IF NOT EXISTS estado_comments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      estado_id INTEGER NOT NULL,
      username TEXT NOT NULL,
      display_name TEXT,
      comment TEXT NOT NULL,
      created_at DATETIME DEFAULT (datetime('now','localtime')),
      FOREIGN KEY(estado_id) REFERENCES estados(id) ON DELETE CASCADE
    )` },
  { name: '027_idx_estado_reactions', sql: 'CREATE INDEX IF NOT EXISTS idx_estado_reactions ON estado_reactions(estado_id)' },
  { name: '028_idx_estado_comments',  sql: 'CREATE INDEX IF NOT EXISTS idx_estado_comments ON estado_comments(estado_id)' },
  { name: '029_estados_product_id',   sql: 'ALTER TABLE estados ADD COLUMN product_id INTEGER' },
  { name: '030_estados_product_name', sql: 'ALTER TABLE estados ADD COLUMN product_name TEXT' },
  { name: '031_users_email',          sql: 'ALTER TABLE users ADD COLUMN email TEXT' },
  { name: '032_users_bio',            sql: 'ALTER TABLE users ADD COLUMN bio TEXT' },
  { name: '033_users_nickname',       sql: 'ALTER TABLE users ADD COLUMN nickname TEXT' },
  { name: '034_users_profile_pic',    sql: 'ALTER TABLE users ADD COLUMN profile_pic TEXT' },
  { name: '035_profile_pics_table', sql: `
    CREATE TABLE IF NOT EXISTS profile_pics (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      filename TEXT NOT NULL,
      updated_at DATETIME DEFAULT (datetime('now','localtime'))
    )` },
  { name: '036_products_stock', sql: 'ALTER TABLE products ADD COLUMN stock INTEGER' },
  { name: '037_products_low_stock_threshold', sql: 'ALTER TABLE products ADD COLUMN low_stock_threshold INTEGER' },
  { name: '038_bot_config_table', sql: `
    CREATE TABLE IF NOT EXISTS bot_config (
      id              INTEGER PRIMARY KEY CHECK (id = 1),
      phone_encrypted TEXT,
      status          TEXT NOT NULL DEFAULT 'disconnected',
      paused          INTEGER NOT NULL DEFAULT 0,
      updated_at      TEXT DEFAULT (datetime('now','localtime'))
    )` },
  { name: '039_bot_config_seed', sql: `
    INSERT OR IGNORE INTO bot_config (id, phone_encrypted, status, paused) VALUES (1, NULL, 'disconnected', 0)` },
  { name: '040_customers_wa_jid', sql: 'ALTER TABLE customers ADD COLUMN wa_jid TEXT' },
  // Antes createOrder() solo insertaba en order_items para pedidos
  // multi-producto -- los pedidos de un solo producto (la mayoria) nunca
  // tuvieron su item, asi que /analytics/products y /analytics/summary
  // (que solo leen order_items) los ignoraban por completo. Se rellena con
  // cantidad 1 -- es lo unico que se puede reconstruir de pedidos viejos
  // donde la cantidad real dicha en el mensaje jamas se guardo en ningun lado.
  { name: '041_backfill_order_items', sql: `
    INSERT INTO order_items (order_id, product_id, product_name, product_price, quantity)
    SELECT o.id, o.product_id, o.product_name, o.product_price, 1
    FROM orders o
    WHERE o.product_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id)` },
  // delivered_at se guardaba con datetime('now','localtime') -- hora
  // Colombia (UTC-5) sin marca de zona -- mientras requested_at siempre fue
  // UTC real (Z). julianday() restaba ambas como si fueran UTC, dando
  // tiempos de entrega negativos (~-300 min, exactamente el offset). Se
  // corrigen los valores ya guardados sumando el offset fijo de Colombia
  // (no tiene horario de verano) para volverlos UTC real. El filtro
  // NOT LIKE '%Z' hace la migracion segura de re-ejecutar sin duplicar el ajuste.
  { name: '042_fix_delivered_at_timezone', sql: `
    UPDATE orders
    SET delivered_at = strftime('%Y-%m-%dT%H:%M:%fZ', datetime(delivered_at, '+5 hours'))
    WHERE delivered_at IS NOT NULL AND delivered_at NOT LIKE '%Z'` },
  { name: '043_login_events', sql: `
    CREATE TABLE login_events (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id    INTEGER NOT NULL REFERENCES users(id),
      logged_in_at TEXT NOT NULL
    )` },
  { name: '044_login_events_index', sql: 'CREATE INDEX idx_login_events_user ON login_events(user_id, logged_in_at)' },
  // Antes "Borrar conversacion" hacia DELETE fisico -- se perdia el texto
  // para siempre. Ahora se marca deleted_at (soft-delete): desaparece de
  // la vista normal pero queda intacto en la base para exportar a PDF.
  { name: '045_messages_deleted_at', sql: 'ALTER TABLE messages ADD COLUMN deleted_at TEXT' },
];

function runMigrations(db) {
  db.exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
    name TEXT PRIMARY KEY,
    applied_at TEXT DEFAULT (datetime('now','localtime'))
  )`);

  const applied = new Set(db.prepare('SELECT name FROM schema_migrations').all().map(r => r.name));
  const markApplied = db.prepare('INSERT OR IGNORE INTO schema_migrations (name) VALUES (?)');

  for (const m of MIGRATIONS) {
    if (applied.has(m.name)) continue;
    try {
      db.exec(m.sql);
      markApplied.run(m.name);
    } catch (e) {
      // Instalaciones previas a este tracking ya tienen la columna/tabla —
      // benigno, se marca aplicada. Cualquier otro error de SQL se reporta y
      // NO se marca — se reintentará (y se volverá a loguear) en el próximo
      // arranque hasta que se corrija, en vez de quedar oculto para siempre.
      const benign = /duplicate column|already exists/i.test(e.message);
      if (benign) {
        markApplied.run(m.name);
      } else {
        logger.error({ err: e.message, migration: m.name }, 'Migración falló — se reintentará en el próximo arranque');
      }
    }
  }
}

module.exports = { runMigrations, MIGRATIONS };
