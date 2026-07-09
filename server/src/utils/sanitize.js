'use strict';

// Quita tags/caracteres de control de texto libre para blindar contra XSS
// almacenado -- ninguna vista actual renderiza HTML crudo, pero es
// defensa en profundidad barata y evita que un futuro visor web
// herede el problema sin darse cuenta.
function sanitizeText(str, maxLen) {
  return String(str)
    .replace(/[<>]/g, '')
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
    .trim()
    .slice(0, maxLen);
}

module.exports = { sanitizeText };
