'use strict';
const path = require('path');
const fs   = require('fs');
const logger = require('../utils/logger');

// Historial de ubicaciones de staff -- vive aparte de la DB a proposito:
// un archivo JSON por trabajador, liviano y capado (MAX_ENTRIES), en vez de
// una tabla SQL que crece sin limite con cada ping GPS (cada 30s x N
// trabajadores = miles de filas por dia). La posicion ACTUAL en cambio si
// vive en la DB (staff_locations, una sola fila por user_id) porque el mapa
// en vivo necesita esa lectura rapida e indexada.
const LOCATIONS_DIR = path.join(process.env.APPDATA || process.env.HOME || process.env.USERPROFILE, 'pedidos-bot', 'locations');
fs.mkdirSync(LOCATIONS_DIR, { recursive: true });

const MAX_ENTRIES = 500;

function historyFile(userId) {
  return path.join(LOCATIONS_DIR, `${userId}.json`);
}

function readLocationHistory(userId) {
  try {
    const raw = fs.readFileSync(historyFile(userId), 'utf8');
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

// entry: { name, username, role, lat, lng, accuracy, recorded_at }
function appendLocationHistory(userId, entry) {
  const history = readLocationHistory(userId);
  history.push(entry);
  const trimmed = history.length > MAX_ENTRIES ? history.slice(history.length - MAX_ENTRIES) : history;
  fs.writeFileSync(historyFile(userId), JSON.stringify(trimmed), 'utf8');
}

// Corre una sola vez al arrancar (ver database.js initDB): si staff_locations
// todavia tiene el historico viejo (varias filas por usuario, de antes de
// este cambio), lo vuelca a JSON para no perder el recorrido y despues deja
// una sola fila (la mas reciente) por usuario. Idempotente -- en boots
// siguientes ya no hay nada que archivar.
async function archiveLegacyRows(pool) {
  const { rows: dups } = await pool.query(`
    SELECT user_id FROM staff_locations GROUP BY user_id HAVING COUNT(*) > 1
  `);
  const dupUsers = dups.map(r => r.user_id);
  if (dupUsers.length === 0) return;

  for (const userId of dupUsers) {
    const { rows: userRows } = await pool.query('SELECT username, display_name, role FROM users WHERE id=$1', [userId]);
    const user = userRows[0];
    const { rows } = await pool.query(
      'SELECT lat, lng, accuracy, recorded_at FROM staff_locations WHERE user_id=$1 ORDER BY id ASC', [userId]
    );
    const history = readLocationHistory(userId);
    for (const r of rows) {
      history.push({
        name: user?.display_name || user?.username || 'Desconocido',
        username: user?.username || null,
        role: user?.role || null,
        lat: r.lat, lng: r.lng, accuracy: r.accuracy, recorded_at: r.recorded_at,
      });
    }
    const trimmed = history.length > MAX_ENTRIES ? history.slice(history.length - MAX_ENTRIES) : history;
    fs.writeFileSync(historyFile(userId), JSON.stringify(trimmed), 'utf8');

    await pool.query(`
      DELETE FROM staff_locations WHERE user_id=$1 AND id NOT IN (
        SELECT id FROM staff_locations WHERE user_id=$1 ORDER BY id DESC LIMIT 1
      )
    `, [userId]);
  }
  logger.info({ users: dupUsers.length }, '[locations] historico legado archivado a JSON');
}

module.exports = { readLocationHistory, appendLocationHistory, archiveLegacyRows };
