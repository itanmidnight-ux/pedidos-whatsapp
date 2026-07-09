const express = require('express');
const router  = express.Router();
const jwt     = require('jsonwebtoken');
const bcrypt  = require('bcrypt');
const { getDB } = require('../db/database');

// ── Brute-force protection ────────────────────────────────────
// key = `${username}:${ip}` → { count, lockedUntil }
const attempts = new Map();
const MAX_ATTEMPTS  = 5;
const LOCKOUT_MS    = 15 * 60 * 1000; // 15 min
const CLEANUP_EVERY = 10 * 60 * 1000; // purge stale entries

setInterval(() => {
  const now = Date.now();
  for (const [key, val] of attempts) {
    if (val.lockedUntil && val.lockedUntil < now) attempts.delete(key);
  }
}, CLEANUP_EVERY).unref();

function getIP(req) {
  return (req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown')
    .split(',')[0].trim();
}

function checkLock(key) {
  const a = attempts.get(key);
  if (!a) return null;
  if (a.lockedUntil && Date.now() < a.lockedUntil) {
    const secsLeft = Math.ceil((a.lockedUntil - Date.now()) / 1000);
    return secsLeft;
  }
  return null;
}

function recordFail(key) {
  const a   = attempts.get(key) || { count: 0 };
  a.count  += 1;
  if (a.count >= MAX_ATTEMPTS) a.lockedUntil = Date.now() + LOCKOUT_MS;
  attempts.set(key, a);
}

function clearAttempts(key) {
  attempts.delete(key);
}

// ── Helpers ────────────────────────────────────────────────────
function signToken(user) {
  const token = jwt.sign(
    { id: user.id, username: user.username, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: '30d' }
  );
  return {
    token,
    username:     user.username,
    display_name: user.display_name || user.username,
    role:         user.role,
  };
}

// ── POST /api/auth/token — Login ───────────────────────────────
// El identificador acepta username (admin/worker, sin cambios) O correo
// (clientes que se auto-registran -- ver /register). Un solo campo en la
// app, el backend resuelve cual es sin necesitar que el usuario elija.
router.post('/token', (req, res) => {
  const { username, password, pin, device_info } = req.body;
  if (!username || typeof username !== 'string' || !username.trim())
    return res.status(400).json({ error: 'Usuario o correo requerido' });

  const credential = password !== undefined
    ? String(password)
    : pin !== undefined ? String(pin) : '';
  if (!credential.length)
    return res.status(400).json({ error: 'Contraseña requerida' });

  const identifier = username.trim().toLowerCase();
  const ip      = getIP(req);
  const lockKey = `${identifier}:${ip}`;

  const secs = checkLock(lockKey);
  if (secs !== null) {
    return res.status(429).json({
      error:     `Cuenta temporalmente bloqueada. Intenta en ${secs} segundos.`,
      retry_in:  secs,
    });
  }

  // El username de un cliente es su celular normalizado (57 + 10 digitos,
  // ver /register) -- si escribe el celular tal cual lo registro (sin el
  // 57 antepuesto) hay que igual encontrar la cuenta.
  const phoneVariant = normalizeAndValidatePhone(identifier) || identifier;

  const db   = getDB();
  const user = db.prepare(
    'SELECT * FROM users WHERE (username = ? OR username = ? OR email = ?) AND active = 1'
  ).get(identifier, phoneVariant, identifier);

  if (!user) {
    recordFail(lockKey);
    return res.status(401).json({ error: 'Credenciales incorrectas' });
  }

  bcrypt.compare(credential, user.pin || user.password_hash, (err, match) => {
    if (err || !match) {
      recordFail(lockKey);
      const a = attempts.get(lockKey);
      const remaining = Math.max(0, MAX_ATTEMPTS - (a?.count || 0));
      return res.status(401).json({
        error:     'Credenciales incorrectas',
        attempts_left: remaining,
      });
    }
    clearAttempts(lockKey);
    // Hora de entrada -- solo staff (admin/worker); clientes no marcan turno
    if (['admin', 'worker'].includes(user.role)) {
      db.prepare(`INSERT INTO login_events (user_id, logged_in_at, device_info) VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ','now'), ?)`)
        .run(user.id, device_info ? sanitizeText(device_info, 200) : null);
    }
    res.json(signToken(user));
  });
});

// ── POST /api/auth/logout — Marca la hora de salida ───────────
// JWT es sin estado -- "logout" real solo existe si el cliente lo marca.
// Se actualiza la fila de login_events mas reciente sin salida registrada
// para saber cuando un trabajador se desconecto (control de asistencia).
router.post('/logout', require('../middleware/auth').clientAuth, (req, res) => {
  // SQLite estandar no soporta ORDER BY/LIMIT en UPDATE -- se resuelve con
  // subquery para agarrar solo la fila abierta mas reciente de ese usuario.
  getDB().prepare(`
    UPDATE login_events SET logged_out_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
    WHERE id = (
      SELECT id FROM login_events
      WHERE user_id = ? AND logged_out_at IS NULL
      ORDER BY id DESC LIMIT 1
    )
  `).run(req.user.id);
  res.json({ ok: true });
});

// ── POST /api/auth/refresh — Renovar token ────────────────────
router.post('/refresh', (req, res) => {
  const auth = req.headers.authorization || '';
  const old  = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!old) return res.status(401).json({ error: 'Token requerido' });

  let payload;
  try {
    // Allow expired tokens (up to 7 extra days) so refresh still works
    payload = jwt.verify(old, process.env.JWT_SECRET, { ignoreExpiration: true });
  } catch {
    return res.status(401).json({ error: 'Token inválido' });
  }

  // Reject if expired more than 7 days ago
  if (payload.exp && (Date.now() / 1000 - payload.exp) > 7 * 86400) {
    return res.status(401).json({ error: 'Sesión expirada. Inicia sesión nuevamente.' });
  }

  const db   = getDB();
  const user = db.prepare(
    'SELECT * FROM users WHERE id = ? AND active = 1'
  ).get(payload.id);
  if (!user) return res.status(401).json({ error: 'Usuario no encontrado' });

  res.json(signToken(user));
});

const { sanitizeText } = require('../utils/sanitize');

// Mismo criterio de normalizacion de celular usado en todo el proyecto
// (waBot.js, order_card.dart, message.dart): 10 digitos que empiezan en
// 3 -> se antepone 57. Cualquier otra cosa se rechaza -- no es celular
// colombiano valido.
function normalizeAndValidatePhone(raw) {
  const digits = String(raw || '').replace(/\D/g, '');
  if (digits.length === 10 && digits.startsWith('3')) return '57' + digits;
  if (digits.length === 12 && digits.startsWith('573')) return digits;
  return null;
}

// ── POST /api/auth/register — Self-registration for clients ───
router.post('/register', async (req, res) => {
  const { password, email, display_name, address, nickname, bio, phone } = req.body;

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email).trim()))
    return res.status(400).json({ error: 'Correo electrónico inválido' });
  if (!password || String(password).length < 8)
    return res.status(400).json({ error: 'La contraseña debe tener mínimo 8 caracteres' });
  if (!display_name || String(display_name).trim().length < 2)
    return res.status(400).json({ error: 'Nombre completo requerido' });
  if (!address || String(address).trim().length < 5)
    return res.status(400).json({ error: 'Dirección de entrega requerida' });

  const normalizedPhone = normalizeAndValidatePhone(phone);
  if (!normalizedPhone)
    return res.status(400).json({ error: 'Número de celular inválido (debe ser un celular colombiano de 10 dígitos, ej: 3138207044)' });

  const db = getDB();
  // El username ya no lo elige el cliente -- se deriva del celular
  // (unico, sin caracteres raros, y sirve de paso para que cart.js
  // pueda usar el mismo valor como telefono real al armar el pedido).
  const name = normalizedPhone;

  if (db.prepare('SELECT id FROM users WHERE username = ?').get(name))
    return res.status(409).json({ error: 'Ese número de celular ya está registrado' });
  if (db.prepare('SELECT id FROM users WHERE email = ?').get(String(email).trim().toLowerCase()))
    return res.status(409).json({ error: 'El correo electrónico ya está registrado' });

  const ip      = getIP(req);
  const lockKey = `register:${ip}`;
  const secs    = checkLock(lockKey);
  if (secs !== null)
    return res.status(429).json({ error: `Demasiados intentos. Espera ${secs} segundos.`, retry_in: secs });

  try {
    const hash = await bcrypt.hash(String(password), 10);
    // active=1: la cuenta queda activa de inmediato -- pedir aprobacion
    // manual de un admin por cada registro no era practico. El correo
    // unico (indice UNIQUE en la base) es la validacion real: evita que
    // se repitan cuentas para la misma persona.
    db.prepare(
      `INSERT INTO users (username, password_hash, pin, display_name, role, active, email, address, nickname, bio, phone)
       VALUES (?,?,?,?,?,1,?,?,?,?,?)`
    ).run(
      name, hash, hash,
      sanitizeText(display_name, 100),
      'client',
      String(email).trim().toLowerCase().slice(0, 200),
      sanitizeText(address, 300),
      nickname ? sanitizeText(nickname, 50) : null,
      bio      ? sanitizeText(bio, 500)      : null,
      normalizedPhone,
    );
    clearAttempts(lockKey);
    res.status(201).json({
      pending: false,
      message: 'Cuenta creada. Ya puedes iniciar sesión con tu correo y contraseña.',
    });
  } catch (e) {
    recordFail(lockKey);
    // UNIQUE (username, email o phone) -- puede pasar por carrera entre
    // el chequeo de arriba y el insert real, aunque sea poco probable.
    if (String(e.message || '').includes('UNIQUE constraint failed')) {
      return res.status(409).json({ error: 'Ese celular o correo ya está registrado' });
    }
    res.status(500).json({ error: 'Error al crear cuenta' });
  }
});

module.exports = router;
