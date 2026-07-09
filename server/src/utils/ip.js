'use strict';

// Mismo criterio usado en auth.js desde el inicio: primer valor de
// X-Forwarded-For (el cliente real cuando hay proxy/tunel delante), o el
// socket directo si no hay proxy.
function getIP(req) {
  return (req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown')
    .split(',')[0].trim();
}

module.exports = { getIP };
