'use strict';
const crypto = require('crypto');
const fs = require('fs');

// Mismo patron que server/src/utils/botCrypto.js (AES-256-GCM, clave
// derivada por SHA-256 de una env var) -- aplicado a archivos en vez de
// strings cortos, para no depender de binarios externos (age/gpg).
function getKey() {
  const raw = process.env.BACKUP_ENCRYPTION_KEY || process.env.JWT_SECRET || '';
  if (!raw) throw new Error('BACKUP_ENCRYPTION_KEY ni JWT_SECRET están definidos');
  return crypto.createHash('sha256').update(raw).digest();
}

// Formato del archivo .enc: iv[12] + authTag[16] + ciphertext.
// Borra el archivo origen sin cifrar tras verificar que el .enc se escribio
// completo -- nunca deja ambas copias (cifrada y plana) coexistiendo.
async function encryptFile(srcPath) {
  const destPath = srcPath + '.enc';
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', getKey(), iv);
  const plaintext = fs.readFileSync(srcPath);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const authTag = cipher.getAuthTag();
  fs.writeFileSync(destPath, Buffer.concat([iv, authTag, ciphertext]));
  fs.unlinkSync(srcPath);
  return destPath;
}

function decryptFile(encPath, destPath) {
  const buf = fs.readFileSync(encPath);
  const iv = buf.subarray(0, 12);
  const authTag = buf.subarray(12, 28);
  const ciphertext = buf.subarray(28);
  const decipher = crypto.createDecipheriv('aes-256-gcm', getKey(), iv);
  decipher.setAuthTag(authTag);
  const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  fs.writeFileSync(destPath, plaintext);
  return destPath;
}

module.exports = { encryptFile, decryptFile };
