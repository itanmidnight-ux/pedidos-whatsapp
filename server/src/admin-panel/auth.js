'use strict';
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { parseCookies } = require('./cookies');

// Verificacion LOCAL del JWT (mismo JWT_SECRET que el server principal,
// EnvironmentFile=mismo .env) -- evita una llamada de red por cada vista.
// La revocacion real (logout) sigue viviendo en el server principal
// (tabla revoked_tokens / Redis) y se respeta porque cada accion de
// escritura (guardar producto, subir imagen) SI pasa por la API real, que
// vuelve a validar el token ahi. Si alguien revoco la sesion, la proxima
// escritura falla con 401 aunque esta vista local no lo detecte de
// inmediato -- lectura vs. escritura, no es una brecha de seguridad real.
function requireAdmin(req, res, next) {
  const cookies = parseCookies(req);
  const token = cookies.token;
  if (!token) return res.redirect('/login');
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    if (payload.role !== 'admin') return res.status(403).send('Se requieren permisos de administrador.');
    req.adminToken = token;
    req.adminUser = payload;
    next();
  } catch {
    return res.redirect('/login');
  }
}

function csrfToken(req) {
  return parseCookies(req).csrf || '';
}

function verifyCsrf(req, res, next) {
  const cookieVal = parseCookies(req).csrf;
  const bodyVal = req.body?._csrf;
  if (!cookieVal || !bodyVal || cookieVal !== bodyVal) {
    return res.status(403).send('Token de seguridad inválido — recarga la página e intenta de nuevo.');
  }
  next();
}

function newCsrfToken() {
  return crypto.randomBytes(24).toString('hex');
}

module.exports = { requireAdmin, csrfToken, verifyCsrf, newCsrfToken };
