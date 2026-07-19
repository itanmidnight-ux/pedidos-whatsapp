-- Schema consolidado para PostgreSQL. Reemplaza el schema.sql + 65
-- migraciones incrementales que existieron mientras el motor era SQLite --
-- una instalacion Postgres siempre arranca desde cero, asi que no hay
-- historial que preservar: esto YA es el estado final de cada tabla.
-- Fechas: se guardan como TEXT en formato ISO-8601 UTC ("...T...Z"), NO como
-- TIMESTAMP/TIMESTAMPTZ nativo -- el driver `pg` devuelve TIMESTAMPTZ como
-- objeto Date de JS, y gran parte del codigo (server + Flutter + PDFs/Excel)
-- espera un string. Mantenerlo TEXT evita reescribir cada sitio que hace
-- string ops sobre estas columnas durante el cutover.
-- Booleans: se mantienen como INTEGER 0/1 (no BOOLEAN nativo) por la misma
-- razon -- el codigo existente compara con `=== 1` / truthy en JS.

-- Helper reutilizado en vez de repetir el to_char(...) largo en cada
-- INSERT/UPDATE manual del codigo de aplicacion (los DEFAULT de columna
-- abajo lo usan directo, sin pasar por la funcion, por simplicidad de DDL).
CREATE OR REPLACE FUNCTION now_iso() RETURNS TEXT AS $$
  SELECT to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
$$ LANGUAGE SQL STABLE;

CREATE TABLE IF NOT EXISTS schema_migrations (
  name TEXT PRIMARY KEY,
  applied_at TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS users (
  id            SERIAL PRIMARY KEY,
  username      TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  pin           TEXT,
  display_name  TEXT,
  role          TEXT DEFAULT 'worker',
  active        INTEGER DEFAULT 1,
  address       TEXT,
  email         TEXT,
  bio           TEXT,
  nickname      TEXT,
  profile_pic   TEXT,
  phone         TEXT,
  created_at    TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique ON users(email) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_unique ON users(phone) WHERE phone IS NOT NULL;

CREATE TABLE IF NOT EXISTS customers (
  id             SERIAL PRIMARY KEY,
  phone          TEXT UNIQUE NOT NULL,
  name           TEXT,
  profile_pic_url TEXT,
  archived       INTEGER DEFAULT 0,
  wa_jid         TEXT,
  created_at     TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS products (
  id                  SERIAL PRIMARY KEY,
  name                TEXT NOT NULL,
  aliases             TEXT DEFAULT '[]',
  price               DOUBLE PRECISION NOT NULL,
  available           INTEGER DEFAULT 1,
  favorite            INTEGER DEFAULT 0,
  no_fiado            INTEGER DEFAULT 0,
  stock               INTEGER,
  low_stock_threshold INTEGER,
  category            TEXT,
  description         TEXT,
  sku                 TEXT,
  created_at          TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);

CREATE TABLE IF NOT EXISTS product_images (
  id         SERIAL PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  filename   TEXT NOT NULL,
  created_at TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS messages (
  id            SERIAL PRIMARY KEY,
  phone         TEXT NOT NULL,
  customer_name TEXT,
  content       TEXT NOT NULL,
  direction     TEXT NOT NULL DEFAULT 'inbound',
  sent          INTEGER DEFAULT 0,
  flagged       INTEGER DEFAULT 0,
  flag_reason   TEXT,
  type          TEXT DEFAULT 'direct',
  media_type    TEXT,
  media_url     TEXT,
  deleted_at    TEXT,
  created_at    TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);
CREATE INDEX IF NOT EXISTS idx_messages_phone ON messages(phone);

-- LISTEN/NOTIFY para el bot de WhatsApp (waBot.js): en vez de que el bot
-- solo se entere de mensajes salientes nuevos por polling periodico (hasta
-- POLL_MS de latencia), Postgres avisa apenas se inserta uno -- el bot los
-- envia casi al instante. El polling periodico se mantiene como red de
-- seguridad (por si el LISTEN se cae), solo que con un intervalo mas largo.
CREATE OR REPLACE FUNCTION notify_outbound_message() RETURNS trigger AS $$
BEGIN
  IF NEW.direction = 'outbound' AND NEW.sent = 0 THEN
    PERFORM pg_notify('outbound_message', NEW.id::text);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_outbound_message ON messages;
CREATE TRIGGER trg_notify_outbound_message
  AFTER INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION notify_outbound_message();

CREATE TABLE IF NOT EXISTS orders (
  id               SERIAL PRIMARY KEY,
  customer_id      INTEGER REFERENCES customers(id),
  product_id       INTEGER,
  product_name     TEXT NOT NULL,
  product_price    DOUBLE PRECISION,
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
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_claimed_by ON orders(claimed_by);

CREATE TABLE IF NOT EXISTS order_items (
  id            SERIAL PRIMARY KEY,
  order_id      INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id    INTEGER,
  product_name  TEXT NOT NULL,
  product_price DOUBLE PRECISION,
  quantity      INTEGER DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

CREATE TABLE IF NOT EXISTS pending_orders (
  id               SERIAL PRIMARY KEY,
  phone            TEXT UNIQUE NOT NULL,
  product_id       INTEGER,
  product_name     TEXT,
  delivery_address TEXT,
  is_fiado         INTEGER DEFAULT 0,
  customer_name    TEXT,
  wa_message       TEXT,
  missing_field    TEXT,
  pending_items    TEXT DEFAULT '[]',
  created_at       TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS client_orders (
  id              SERIAL PRIMARY KEY,
  client_username TEXT NOT NULL,
  items_json      TEXT NOT NULL,
  total           DOUBLE PRECISION NOT NULL,
  payment_method  TEXT NOT NULL,
  nequi_reference TEXT,
  status          TEXT DEFAULT 'pending',
  delivery_date   TEXT,
  created_at      TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS promotional_campaigns (
  id          SERIAL PRIMARY KEY,
  message     TEXT NOT NULL,
  target_type TEXT DEFAULT 'all',
  sent_count  INTEGER DEFAULT 0,
  created_by  INTEGER REFERENCES users(id),
  created_at  TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS estados (
  id             SERIAL PRIMARY KEY,
  admin_username TEXT NOT NULL,
  filename       TEXT NOT NULL,
  media_type     TEXT NOT NULL DEFAULT 'image',
  caption        TEXT,
  product_id     INTEGER,
  product_name   TEXT,
  created_at     TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
  expires_at     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS estado_reactions (
  id         SERIAL PRIMARY KEY,
  estado_id  INTEGER NOT NULL REFERENCES estados(id) ON DELETE CASCADE,
  username   TEXT NOT NULL,
  created_at TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
  UNIQUE(estado_id, username)
);
CREATE INDEX IF NOT EXISTS idx_estado_reactions ON estado_reactions(estado_id);

CREATE TABLE IF NOT EXISTS estado_comments (
  id           SERIAL PRIMARY KEY,
  estado_id    INTEGER NOT NULL REFERENCES estados(id) ON DELETE CASCADE,
  username     TEXT NOT NULL,
  display_name TEXT,
  comment      TEXT NOT NULL,
  created_at   TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);
CREATE INDEX IF NOT EXISTS idx_estado_comments ON estado_comments(estado_id);

CREATE TABLE IF NOT EXISTS cart_items (
  id              SERIAL PRIMARY KEY,
  client_username TEXT NOT NULL,
  product_id      INTEGER NOT NULL,
  quantity        INTEGER NOT NULL DEFAULT 1,
  delivery_date   TEXT,
  created_at      TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS profile_pics (
  id         SERIAL PRIMARY KEY,
  username   TEXT NOT NULL UNIQUE,
  filename   TEXT NOT NULL,
  updated_at TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS bot_config (
  id              INTEGER PRIMARY KEY CHECK (id = 1),
  phone_encrypted TEXT,
  status          TEXT NOT NULL DEFAULT 'disconnected',
  paused          INTEGER NOT NULL DEFAULT 0,
  updated_at      TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);
INSERT INTO bot_config (id, phone_encrypted, status, paused)
  VALUES (1, NULL, 'disconnected', 0) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS nequi_config (
  id                INTEGER PRIMARY KEY CHECK (id = 1),
  phone_encrypted   TEXT,
  account_name      TEXT,
  api_key_encrypted TEXT,
  status            TEXT NOT NULL DEFAULT 'disconnected',
  connected_at      TEXT,
  updated_at        TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);
INSERT INTO nequi_config (id, status) VALUES (1, 'disconnected') ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS login_events (
  id            SERIAL PRIMARY KEY,
  user_id       INTEGER NOT NULL REFERENCES users(id),
  logged_in_at  TEXT NOT NULL,
  logged_out_at TEXT,
  device_info   TEXT
);
CREATE INDEX IF NOT EXISTS idx_login_events_user ON login_events(user_id, logged_in_at);

CREATE TABLE IF NOT EXISTS staff_locations (
  id          SERIAL PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  lat         DOUBLE PRECISION NOT NULL,
  lng         DOUBLE PRECISION NOT NULL,
  accuracy    DOUBLE PRECISION,
  recorded_at TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);
CREATE INDEX IF NOT EXISTS idx_staff_locations_user ON staff_locations(user_id, recorded_at DESC);

CREATE TABLE IF NOT EXISTS ip_activity (
  ip              TEXT NOT NULL,
  minute          TEXT NOT NULL,
  requests        INTEGER NOT NULL DEFAULT 0,
  count_401       INTEGER NOT NULL DEFAULT 0,
  count_403       INTEGER NOT NULL DEFAULT 0,
  count_404       INTEGER NOT NULL DEFAULT 0,
  count_auth_fail INTEGER DEFAULT 0,
  last_path       TEXT,
  last_user_agent TEXT,
  PRIMARY KEY (ip, minute)
);
CREATE INDEX IF NOT EXISTS idx_ip_activity_minute ON ip_activity(minute);

CREATE TABLE IF NOT EXISTS security_alerts (
  id         SERIAL PRIMARY KEY,
  kind       TEXT NOT NULL,
  message    TEXT NOT NULL,
  read_at    TEXT,
  created_at TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS blocked_ips (
  ip         TEXT PRIMARY KEY,
  reason     TEXT,
  blocked_at TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);

CREATE TABLE IF NOT EXISTS revoked_tokens (
  jti        TEXT PRIMARY KEY,
  user_id    INTEGER,
  revoked_at TEXT DEFAULT (to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
);
