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
router.post('/token', (req, res) => {
  const { username, password, pin } = req.body;
  if (!username || typeof username !== 'string' || !username.trim())
    return res.status(400).json({ error: 'Usuario requerido' });

  const credential = password !== undefined
    ? String(password)
    : pin !== undefined ? String(pin) : '';
  if (!credential.length)
    return res.status(400).json({ error: 'Contraseña requerida' });

  const ip      = getIP(req);
  const lockKey = `${username.trim().toLowerCase()}:${ip}`;

  const secs = checkLock(lockKey);
  if (secs !== null) {
    return res.status(429).json({
      error:     `Cuenta temporalmente bloqueada. Intenta en ${secs} segundos.`,
      retry_in:  secs,
    });
  }

  const db   = getDB();
  const user = db.prepare(
    'SELECT * FROM users WHERE username = ? AND active = 1'
  ).get(username.trim().toLowerCase());

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
    res.json(signToken(user));
  });
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

// ── POST /api/auth/register — Self-registration for clients ───
router.post('/register', async (req, res) => {
  const { username, password, email, display_name, address, nickname, bio } = req.body;

  if (!username || typeof username !== 'string' || username.trim().length < 2)
    return res.status(400).json({ error: 'Nombre de usuario requerido (mín 2 caracteres)' });
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email).trim()))
    return res.status(400).json({ error: 'Correo electrónico inválido' });
  if (!password || String(password).length < 8)
    return res.status(400).json({ error: 'La contraseña debe tener mínimo 8 caracteres' });
  if (!display_name || String(display_name).trim().length < 2)
    return res.status(400).json({ error: 'Nombre completo requerido' });
  if (!address || String(address).trim().length < 5)
    return res.status(400).json({ error: 'Dirección de entrega requerida' });

  const db   = getDB();
  const name = username.trim().toLowerCase().replace(/[^a-z0-9._-]/g, '');
  if (name.length < 2)
    return res.status(400).json({ error: 'Nombre de usuario inválido (solo letras, números, puntos, guiones)' });

  if (db.prepare('SELECT id FROM users WHERE username = ?').get(name))
    return res.status(409).json({ error: 'El nombre de usuario ya existe' });
  if (db.prepare('SELECT id FROM users WHERE email = ?').get(String(email).trim().toLowerCase()))
    return res.status(409).json({ error: 'El correo electrónico ya está registrado' });

  const ip      = getIP(req);
  const lockKey = `register:${ip}`;
  const secs    = checkLock(lockKey);
  if (secs !== null)
    return res.status(429).json({ error: `Demasiados intentos. Espera ${secs} segundos.`, retry_in: secs });

  try {
    const hash = await bcrypt.hash(String(password), 10);
    // active=0: cuenta queda pendiente de aprobación del admin (users_screen ya tiene el toggle)
    db.prepare(
      `INSERT INTO users (username, password_hash, pin, display_name, role, active, email, address, nickname, bio)
       VALUES (?,?,?,?,?,0,?,?,?,?)`
    ).run(
      name, hash, hash,
      String(display_name).trim().slice(0, 100),
      'client',
      String(email).trim().toLowerCase().slice(0, 200),
      String(address).trim().slice(0, 300),
      nickname ? String(nickname).trim().slice(0, 50) : null,
      bio      ? String(bio).trim().slice(0, 500)      : null,
    );
    clearAttempts(lockKey);
    res.status(201).json({
      pending: true,
      message: 'Cuenta creada. Un administrador debe aprobarla antes de que puedas iniciar sesión.',
    });
  } catch (e) {
    recordFail(lockKey);
    res.status(500).json({ error: 'Error al crear cuenta' });
  }
});

module.exports = router;
