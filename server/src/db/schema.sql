CREATE TABLE IF NOT EXISTS users (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  username     TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  pin          TEXT,
  display_name TEXT,
  role         TEXT DEFAULT 'worker',
  active       INTEGER DEFAULT 1,
  created_at   TEXT DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS customers (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  phone      TEXT UNIQUE NOT NULL,
  name       TEXT,
  created_at TEXT DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS products (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  aliases    TEXT DEFAULT '[]',
  price      REAL NOT NULL,
  available  INTEGER DEFAULT 1,
  favorite   INTEGER DEFAULT 0,
  no_fiado   INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS messages (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  phone         TEXT NOT NULL,
  customer_name TEXT,
  content       TEXT NOT NULL,
  direction     TEXT NOT NULL DEFAULT 'inbound',
  sent          INTEGER DEFAULT 0,
  flagged       INTEGER DEFAULT 0,
  flag_reason   TEXT,
  created_at    TEXT DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_messages_phone ON messages(phone);

CREATE TABLE IF NOT EXISTS orders (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id      INTEGER REFERENCES customers(id),
  product_id       INTEGER,
  product_name     TEXT NOT NULL,
  product_price    REAL,
  delivery_address TEXT,
  is_fiado         INTEGER DEFAULT 0,
  status           TEXT DEFAULT 'pending',
  claimed_by       INTEGER REFERENCES users(id),
  claimed_at       TEXT,
  cancel_reason    TEXT,
  wa_message       TEXT,
  comment          TEXT,
  requested_at     TEXT NOT NULL,
  delivered_at     TEXT,
  pdf_exported     INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS order_items (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id      INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id    INTEGER,
  product_name  TEXT NOT NULL,
  product_price REAL,
  quantity      INTEGER DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

CREATE TABLE IF NOT EXISTS promotional_campaigns (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  message     TEXT NOT NULL,
  target_type TEXT DEFAULT 'all',
  sent_count  INTEGER DEFAULT 0,
  created_by  INTEGER REFERENCES users(id),
  created_at  TEXT DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS pending_orders (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  phone            TEXT UNIQUE NOT NULL,
  product_id       INTEGER,
  product_name     TEXT,
  delivery_address TEXT,
  is_fiado         INTEGER DEFAULT 0,
  customer_name    TEXT,
  wa_message       TEXT,
  missing_field    TEXT,
  pending_items    TEXT DEFAULT '[]',
  created_at       TEXT DEFAULT (datetime('now','localtime'))
);
