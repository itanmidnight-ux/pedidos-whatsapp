const jwt = require('jsonwebtoken');
const crypto = require('crypto');

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

function jwtAuth(req, res, next) {
  const header = req.headers['authorization'];
  if (!header?.startsWith('Bearer '))
    return res.status(401).json({ error: 'Token requerido' });
  try {
    const payload = jwt.verify(header.slice(7), process.env.JWT_SECRET);
    const { getDB } = require('../db/database');
    // payload.jti puede no existir en tokens emitidos antes de este cambio --
    // esos simplemente no son revocables individualmente (expiran solos).
    if (payload.jti) {
      const revoked = getDB().prepare('SELECT 1 FROM revoked_tokens WHERE jti = ?').get(payload.jti);
      if (revoked) return res.status(401).json({ error: 'Sesión cerrada' });
    }
    const dbUser = getDB().prepare('SELECT id, username, role, display_name, active FROM users WHERE id = ?').get(payload.id);
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

module.exports = { apiKeyAuth, jwtAuth, adminAuth, staffAuth, clientAuth, verifyWebhookSignature };
