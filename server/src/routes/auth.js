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

module.exports = router;
