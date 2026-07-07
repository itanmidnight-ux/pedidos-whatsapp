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
    const dbUser = getDB().prepare('SELECT id, username, role, display_name, active FROM users WHERE id = ?').get(payload.id);
    if (!dbUser || !dbUser.active)
      return res.status(401).json({ error: 'Cuenta desactivada o inexistente' });
    // Usar rol/estado actual de la DB, no el congelado en el token
    req.user = { id: dbUser.id, username: dbUser.username, role: dbUser.role, display_name: dbUser.display_name };
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

module.exports = { apiKeyAuth, jwtAuth, adminAuth, staffAuth, clientAuth };
