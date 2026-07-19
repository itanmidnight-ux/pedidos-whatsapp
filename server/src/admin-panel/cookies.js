'use strict';
// Parser/writer de cookies minimo -- el panel solo maneja 2 cookies propias
// (token, csrf), no vale la pena una dependencia extra (cookie-parser) para eso.

function parseCookies(req) {
  const header = req.headers.cookie;
  const out = {};
  if (!header) return out;
  for (const part of header.split(';')) {
    const idx = part.indexOf('=');
    if (idx === -1) continue;
    const key = part.slice(0, idx).trim();
    const val = part.slice(idx + 1).trim();
    if (key) out[key] = decodeURIComponent(val);
  }
  return out;
}

function setCookie(res, name, value, { maxAgeMs, httpOnly = true } = {}) {
  const parts = [`${name}=${encodeURIComponent(value)}`, 'Path=/', 'SameSite=Strict'];
  if (httpOnly) parts.push('HttpOnly');
  if (maxAgeMs) parts.push(`Max-Age=${Math.floor(maxAgeMs / 1000)}`);
  // Secure se omite a proposito: el panel solo se accede via 127.0.0.1 (HTTP
  // plano, sin TLS local) o mas adelante via VPN -- exigir Secure aqui
  // rompería la cookie en ese escenario. El aislamiento real es de red
  // (bind 127.0.0.1 + firewall + VPN), no la cookie.
  res.setHeader('Set-Cookie', [...(res.getHeader('Set-Cookie') || []), parts.join('; ')]);
}

function clearCookie(res, name) {
  res.setHeader('Set-Cookie', [...(res.getHeader('Set-Cookie') || []), `${name}=; Path=/; Max-Age=0`]);
}

module.exports = { parseCookies, setCookie, clearCookie };
