const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { getRedisClient, isRedisReady } = require('../utils/redisClient');

const REVOKED_PREFIX = 'jwt:revoked:';

// Cache rapida de revocacion: Redis (si esta disponible) evita pegarle a
// SQLite en cada request autenticado. La tabla `revoked_tokens` sigue
// siendo la fuente de verdad -- si Redis no dice "revocado" (porque no
// esta configurado, esta caido, o el jti no se alcanzo a espejar), el
// chequeo cae igual a la tabla, nunca se salta la verificacion real.
async function isRevokedFast(jti) {
  const redis = getRedisClient();
  if (!redis || !isRedisReady()) return false;
  try { return !!(await redis.exists(REVOKED_PREFIX + jti)); } catch { return false; }
}

function mirrorRevocation(jti) {
  const redis = getRedisClient();
  if (!redis || !isRedisReady()) return;
  // TTL 30d = misma vida maxima que un JWT (ver signToken en routes/auth.js)
  redis.set(REVOKED_PREFIX + jti, '1', 'EX', 30 * 24 * 60 * 60).catch(() => {});
}

function apiKeyAuth(req, res, next) {
  const key = req.headers['x-api-key'];
  const expected = process.env.API_KEY || '';
  const keyBuf = Buffer.from(String(key || ''));
  const expectedBuf = Buffer.from(expected);
  const valid = keyBuf.length === expectedBuf.length && crypto.timingSafeEqual(keyBuf, expectedBuf);
  if (!key || !expected || !valid)
    return res.status(401).json({ error: 'API Key inválida' });
  next();
}

async function jwtAuth(req, res, next) {
  const header = req.headers['authorization'];
  if (!header?.startsWith('Bearer '))
    return res.status(401).json({ error: 'Token requerido' });
  try {
    const payload = jwt.verify(header.slice(7), process.env.JWT_SECRET);
    const { getDB } = require('../db/database');
    // payload.jti puede no existir en tokens emitidos antes de este cambio --
    // esos simplemente no son revocables individualmente (expiran solos).
    if (payload.jti) {
      if (await isRevokedFast(payload.jti)) return res.status(401).json({ error: 'Sesión cerrada' });
      const { rows: revokedRows } = await getDB().query('SELECT 1 FROM revoked_tokens WHERE jti = $1', [payload.jti]);
      if (revokedRows[0]) return res.status(401).json({ error: 'Sesión cerrada' });
    }
    const { rows: userRows } = await getDB().query('SELECT id, username, role, display_name, active FROM users WHERE id = $1', [payload.id]);
    const dbUser = userRows[0];
    if (!dbUser || !dbUser.active)
      return res.status(401).json({ error: 'Cuenta desactivada o inexistente' });
    // Usar rol/estado actual de la DB, no el congelado en el token
    req.user = { id: dbUser.id, username: dbUser.username, role: dbUser.role, display_name: dbUser.display_name, jti: payload.jti };
    next();
  } catch {
    return res.status(401).json({ error: 'Token inválido o expirado' });
  }
}

function adminAuth(req, res, next) {
  jwtAuth(req, res, () => {
    if (req.user?.role !== 'admin')
      return res.status(403).json({ error: 'Se requieren permisos de administrador' });
    next();
  });
}

// Solo staff (admin/worker) — para gestión de pedidos y mensajería del negocio
function staffAuth(req, res, next) {
  jwtAuth(req, res, () => {
    if (!['admin', 'worker'].includes(req.user?.role))
      return res.status(403).json({ error: 'Acceso denegado' });
    next();
  });
}

function clientAuth(req, res, next) {
  jwtAuth(req, res, () => {
    if (!['admin', 'worker', 'client'].includes(req.user?.role))
      return res.status(403).json({ error: 'Acceso denegado' });
    next();
  });
}

function verifyWebhookSignature(req, res, next) {
  const secret = process.env.WEBHOOK_SECRET;
  if (!secret) return res.status(401).json({ error: 'Webhook no configurado' });

  const signature = req.headers['x-baileys-signature'];
  const timestamp = req.headers['x-baileys-timestamp'];
  if (!signature || !timestamp) return res.status(401).json({ error: 'Firma requerida' });

  const age = Math.abs(Date.now() - Number(timestamp));
  if (!Number.isFinite(age) || age > 5 * 60 * 1000)
    return res.status(401).json({ error: 'Timestamp fuera de ventana' });

  const expected = crypto.createHmac('sha256', secret)
    .update(JSON.stringify(req.body) + ':' + timestamp).digest('hex');
  const sigBuf = Buffer.from(String(signature));
  const expBuf = Buffer.from(expected);
  const valid = sigBuf.length === expBuf.length && crypto.timingSafeEqual(sigBuf, expBuf);
  if (!valid) return res.status(401).json({ error: 'Firma inválida' });
  next();
}

module.exports = { apiKeyAuth, jwtAuth, adminAuth, staffAuth, clientAuth, verifyWebhookSignature, mirrorRevocation };
