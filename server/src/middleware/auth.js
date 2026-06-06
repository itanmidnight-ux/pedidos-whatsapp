const jwt = require('jsonwebtoken');

function apiKeyAuth(req, res, next) {
  const key = req.headers['x-api-key'];
  if (!key || key !== process.env.API_KEY)
    return res.status(401).json({ error: 'API Key inválida' });
  next();
}

function jwtAuth(req, res, next) {
  const header = req.headers['authorization'];
  if (!header?.startsWith('Bearer '))
    return res.status(401).json({ error: 'Token requerido' });
  try {
    req.user = jwt.verify(header.slice(7), process.env.JWT_SECRET);
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

function clientAuth(req, res, next) {
  jwtAuth(req, res, () => {
    if (!['admin', 'worker', 'client'].includes(req.user?.role))
      return res.status(403).json({ error: 'Acceso denegado' });
    next();
  });
}

module.exports = { apiKeyAuth, jwtAuth, adminAuth, clientAuth };
