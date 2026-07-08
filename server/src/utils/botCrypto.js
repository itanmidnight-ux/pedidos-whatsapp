'use strict';
const crypto = require('crypto');

// Clave derivada de BOT_ENCRYPTION_KEY (recomendado) o, si falta, de JWT_SECRET
// -- documentado en .env.example. sha256 siempre produce 32 bytes, exacto lo
// que pide AES-256-GCM.
function getKey() {
  const raw = process.env.BOT_ENCRYPTION_KEY || process.env.JWT_SECRET || '';
  if (!raw) throw new Error('BOT_ENCRYPTION_KEY ni JWT_SECRET están definidos');
  return crypto.createHash('sha256').update(raw).digest();
}

// Formato de salida: base64(iv[12] + authTag[16] + ciphertext) en un solo campo,
// para no necesitar columnas extra en bot_config.
function encryptPhone(phone) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', getKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(String(phone), 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return Buffer.concat([iv, authTag, ciphertext]).toString('base64');
}

function decryptPhone(blob) {
  const buf = Buffer.from(blob, 'base64');
  const iv = buf.subarray(0, 12);
  const authTag = buf.subarray(12, 28);
  const ciphertext = buf.subarray(28);
  const decipher = crypto.createDecipheriv('aes-256-gcm', getKey(), iv);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
}

module.exports = { encryptPhone, decryptPhone };
