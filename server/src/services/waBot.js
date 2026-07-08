'use strict';
require('dotenv').config();
const path  = require('path');
const fs    = require('fs');
const axios = require('axios');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  fetchLatestBaileysVersion,
  DisconnectReason,
  downloadMediaMessage,
  jidNormalizedUser,
} = require('@whiskeysockets/baileys');
const QRCode  = require('qrcode');
const logger  = require('../utils/logger');
const { getDB } = require('../db/database');
const { encryptPhone, decryptPhone } = require('../utils/botCrypto');

// ── Directorios ───────────────────────────────────────────────
const BOT_DIR   = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot');
const AUTH_DIR  = path.join(BOT_DIR, 'baileys_auth');
const MEDIA_DIR = path.join(BOT_DIR, 'media');
const DOCS_DIR  = path.join(BOT_DIR, 'docs');
for (const d of [AUTH_DIR, MEDIA_DIR, DOCS_DIR]) fs.mkdirSync(d, { recursive: true });

// ── Config ────────────────────────────────────────────────────
const API_URL = `http://localhost:${process.env.PORT || 3000}`;
const API_KEY = process.env.API_KEY;

const baileysLogger = logger.child({ mod: 'baileys' });
baileysLogger.level = 'warn'; // baileys es MUY verboso en debug/info

let sock              = null;
let isReady           = false;
let pollTimer         = null;
let currentQR         = null; // data-URL para el endpoint admin
let reconnectTimer    = null;
let mediaCleanupInterval = null;
let intentionalClose  = false; // true cuando pausamos/deslogueamos nosotros mismos

const POLL_MS = 3000;

// ── Reconexión con backoff exponencial ─────────────────────────
const BASE_RECONNECT_MS = 10_000;
const MAX_RECONNECT_MS  = 5 * 60_000;
const MAX_RECONNECT_ATTEMPTS = parseInt(process.env.BOT_MAX_RECONNECT_ATTEMPTS, 10) || 10;
let reconnectAttempts  = 0;
let reconnectExhausted = false;

// ── Salud / métricas para el panel de admin ────────────────────
let connectedSince = null;
let lastMessageAt  = null;

// ── Límite de mensajes salientes por hora (anti-baneo) ─────────
const MAX_MSGS_PER_HOUR = parseInt(process.env.BOT_MAX_MSGS_PER_HOUR, 10) || 200;
let sentTimestamps = [];
let lastCapWarnAt  = 0;

function canSendMore() {
  const cutoff = Date.now() - 3_600_000;
  sentTimestamps = sentTimestamps.filter(t => t > cutoff);
  return sentTimestamps.length < MAX_MSGS_PER_HOUR;
}

// ── Limpieza de media descargada (evita llenar el disco) ───────
const MEDIA_RETENTION_DAYS = parseInt(process.env.BOT_MEDIA_RETENTION_DAYS, 10) || 30;

function cleanupOldMedia() {
  const cutoff = Date.now() - MEDIA_RETENTION_DAYS * 86_400_000;
  for (const dir of [MEDIA_DIR, DOCS_DIR]) {
    let files;
    try { files = fs.readdirSync(dir); } catch (_) { continue; }
    for (const f of files) {
      const fpath = path.join(dir, f);
      try {
        if (fs.statSync(fpath).mtimeMs < cutoff) fs.unlinkSync(fpath);
      } catch (_) {}
    }
  }
}

const http = axios.create({
  baseURL: API_URL,
  timeout: 15000,
  headers: { 'X-API-Key': API_KEY },
});

// ── Utilidades ────────────────────────────────────────────────
const delay = ms => new Promise(r => setTimeout(r, ms));

function normalizePhone(phone) {
  const d = String(phone).replace(/\D/g, '');
  if (d.length === 10 && d.startsWith('3')) return '57' + d;
  return d;
}

function toJid(phone) {
  return `${normalizePhone(phone)}@s.whatsapp.net`;
}

// ── bot_config (SQLite) ─────────────────────────────────────────
function getBotConfigRow() {
  return getDB().prepare('SELECT * FROM bot_config WHERE id = 1').get();
}

function setDbStatus(status) {
  getDB().prepare(
    `UPDATE bot_config SET status = ?, updated_at = (datetime('now','localtime')) WHERE id = 1`
  ).run(status);
}

function wipeAuthDir() {
  fs.rmSync(AUTH_DIR, { recursive: true, force: true });
  fs.mkdirSync(AUTH_DIR, { recursive: true });
}

async function sendTyping(jid, durationMs = 1500) {
  try {
    await sock.sendPresenceUpdate('composing', jid);
    await delay(durationMs);
    await sock.sendPresenceUpdate('paused', jid);
  } catch (_) {}
}

async function postInbound(phone, name, message, mediaType, mediaUrl, profilePicUrl) {
  try {
    await http.post('/api/webhook/message', {
      phone, name, message,
      media_type:      mediaType    || undefined,
      media_url:       mediaUrl     || undefined,
      profile_pic_url: profilePicUrl || undefined,
      timestamp:       new Date().toISOString(),
    });
    lastMessageAt = new Date().toISOString();
  } catch (e) {
    if (e.response?.status !== 429) logger.error({ err: e.message }, '[bot] webhook err');
  }
}

// ── Descargar y guardar media entrante ──────────────────────────
async function downloadAndSave(msg, phone, ext, destDir = MEDIA_DIR) {
  const buffer = await downloadMediaMessage(msg, 'buffer', {}, { logger: baileysLogger, reuploadRequest: sock.updateMediaMessage });
  const filename = `${phone}_${Date.now()}.${ext}`;
  fs.writeFileSync(path.join(destDir, filename), buffer);
  return filename;
}

// Baileys envuelve el contenido real en mensajes efímeros / view-once —
// hay que desenvolver antes de mirar qué tipo es.
function unwrapMessage(message) {
  if (!message) return message;
  if (message.ephemeralMessage)        return unwrapMessage(message.ephemeralMessage.message);
  if (message.viewOnceMessage)         return unwrapMessage(message.viewOnceMessage.message);
  if (message.viewOnceMessageV2)       return unwrapMessage(message.viewOnceMessageV2.message);
  if (message.documentWithCaptionMessage) return unwrapMessage(message.documentWithCaptionMessage.message);
  return message;
}

// ── Poll mensajes salientes ────────────────────────────────────
async function pollOutbound() {
  if (!isReady || !sock) return;
  try {
    const { data } = await http.get('/api/messages/outbound/pending');
    for (const msg of (data.messages || [])) {
      if (!canSendMore()) {
        const now = Date.now();
        if (now - lastCapWarnAt > 5 * 60_000) {
          lastCapWarnAt = now;
          logger.warn({ max: MAX_MSGS_PER_HOUR }, '[bot] límite de mensajes/hora alcanzado — pausando envíos');
        }
        break;
      }
      try {
        const jid = toJid(msg.phone);

        if (msg.media_url) {
          const inMedia = path.join(MEDIA_DIR, msg.media_url);
          const inDocs  = path.join(DOCS_DIR,  msg.media_url);
          const fpath   = fs.existsSync(inMedia) ? inMedia
                        : fs.existsSync(inDocs)  ? inDocs
                        : null;

          if (fpath) {
            const buffer = fs.readFileSync(fpath);
            const ext    = path.extname(msg.media_url).slice(1).toLowerCase();
            const fname  = path.basename(msg.media_url);

            switch (msg.media_type) {
              case 'image':
                await sock.sendMessage(jid, { image: buffer, caption: msg.caption || '' });
                break;
              case 'video':
                await sock.sendMessage(jid, { video: buffer, caption: msg.caption || '' });
                break;
              case 'audio':
              case 'voice': {
                const mimetype = ext === 'ogg' ? 'audio/ogg; codecs=opus'
                               : ext === 'mp3' ? 'audio/mpeg'
                               : ext === 'aac' ? 'audio/aac'
                               : 'audio/mp4';
                await sock.sendMessage(jid, { audio: buffer, mimetype, ptt: true });
                break;
              }
              default: {
                const mimetype = 'application/octet-stream';
                await sock.sendMessage(jid, { document: buffer, mimetype, fileName: fname });
                break;
              }
            }
          }
        } else {
          await sock.sendMessage(jid, { text: msg.content });
        }

        await http.put(`/api/messages/${msg.id}/sent`);
        sentTimestamps.push(Date.now());
        lastMessageAt = new Date().toISOString();
        await delay(1500 + Math.random() * 2000);
      } catch (e) { logger.error({ err: e.message, orderId: msg.id }, '[bot] send err'); }
    }
  } catch (_) {}
}

// ── Manejar mensajes entrantes ────────────────────────────────
async function handleInbound(msg) {
  if (msg.key.fromMe) return;
  const rawJid = msg.key.remoteJid || '';
  if (!rawJid || rawJid.endsWith('@g.us') || rawJid === 'status@broadcast') return;

  const jid     = jidNormalizedUser(rawJid);
  const phone   = jid.split('@')[0];
  const name    = msg.pushName || phone;

  let profilePicUrl = null;
  try { profilePicUrl = await sock.profilePictureUrl(jid, 'image'); } catch (_) {}

  const content = unwrapMessage(msg.message);
  if (!content) return;
  const type = Object.keys(content)[0];

  // ── AUDIO / NOTA DE VOZ ──────────────────────────────────
  if (type === 'audioMessage') {
    try {
      const isPtt = !!content.audioMessage.ptt;
      const fname = await downloadAndSave(msg, phone, isPtt ? 'ogg' : 'mp4');
      await postInbound(phone, name, isPtt ? '[Nota de voz]' : '[Audio]', 'audio', fname, profilePicUrl);
      await delay(1000);
      await sock.sendMessage(jid, { text: '✅ Audio recibido. Un colaborador lo atenderá pronto.' });
    } catch (e) { logger.error({ err: e.message }, '[bot] audio err'); }
    return;
  }

  // ── IMAGEN ───────────────────────────────────────────────
  if (type === 'imageMessage') {
    try {
      const fname   = await downloadAndSave(msg, phone, 'jpg');
      const caption = content.imageMessage.caption || '[Imagen]';
      await postInbound(phone, name, caption, 'image', fname, profilePicUrl);
      await delay(1000);
      await sock.sendMessage(jid, { text: '✅ Imagen recibida. Un colaborador la revisará pronto.' });
    } catch (e) { logger.error({ err: e.message }, '[bot] image err'); }
    return;
  }

  // ── VIDEO ────────────────────────────────────────────────
  if (type === 'videoMessage') {
    try {
      const fname   = await downloadAndSave(msg, phone, 'mp4');
      const caption = content.videoMessage.caption || '[Video]';
      await postInbound(phone, name, caption, 'video', fname, profilePicUrl);
      await delay(1000);
      await sock.sendMessage(jid, { text: '✅ Video recibido. Un colaborador lo revisará pronto.' });
    } catch (e) { logger.error({ err: e.message }, '[bot] video err'); }
    return;
  }

  // ── DOCUMENTO ────────────────────────────────────────────
  if (type === 'documentMessage') {
    try {
      const origName = content.documentMessage.fileName || 'documento';
      const ext      = origName.includes('.') ? origName.split('.').pop() : 'bin';
      const fname    = await downloadAndSave(msg, phone, ext, DOCS_DIR);
      await postInbound(phone, name, `[Documento: ${origName}]`, 'document', fname, profilePicUrl);
      await delay(1000);
      await sock.sendMessage(jid, { text: '✅ Documento recibido. Un colaborador lo revisará.' });
    } catch (e) { logger.error({ err: e.message }, '[bot] doc err'); }
    return;
  }

  // ── STICKER ──────────────────────────────────────────────
  if (type === 'stickerMessage') {
    try {
      const fname = await downloadAndSave(msg, phone, 'webp');
      await postInbound(phone, name, '[Sticker]', 'image', fname, profilePicUrl);
    } catch (_) {}
    return;
  }

  // ── UBICACIÓN ────────────────────────────────────────────
  if (type === 'locationMessage') {
    const loc     = content.locationMessage;
    const lat     = loc.degreesLatitude;
    const lng     = loc.degreesLongitude;
    const locName = loc.name || '';
    const label   = locName || `${String(lat).slice(0, 9)}, ${String(lng).slice(0, 9)}`;
    const mapsUrl = `https://maps.google.com/?q=${lat},${lng}`;
    await postInbound(phone, name, `📍 Ubicación: ${label}\n${mapsUrl}`, null, null, profilePicUrl);
    return;
  }

  // ── REACCIÓN ─────────────────────────────────────────────
  if (type === 'reactionMessage') {
    await postInbound(phone, name, `[Reacción: ${content.reactionMessage.text || '❤️'}]`, null, null, profilePicUrl);
    return;
  }

  // ── TEXTO ────────────────────────────────────────────────
  const text = (content.conversation || content.extendedTextMessage?.text || '').trim();
  if (!text) return;
  const typingMs = 800 + Math.min(text.length * 18, 2500);
  await sendTyping(jid, typingMs);
  await postInbound(phone, name, text, null, null, profilePicUrl);
}

// ── Conexión / eventos baileys ──────────────────────────────────
async function handleConnectionUpdate(update) {
  const { connection, lastDisconnect, qr } = update;

  if (qr) {
    try {
      currentQR = await QRCode.toDataURL(qr);
      setDbStatus('qr_pending');
      logger.info('[bot] QR listo — GET /api/bot/qr');
    } catch (e) {
      currentQR = null;
      logger.error({ err: e.message }, '[bot] No se pudo generar el QR');
    }
  }

  if (connection === 'open') {
    isReady            = true;
    currentQR          = null;
    connectedSince     = new Date().toISOString();
    reconnectAttempts  = 0;
    reconnectExhausted = false;
    setDbStatus('connected');
    logger.info('[bot] Conectado y listo');
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(pollOutbound, POLL_MS);
  }

  if (connection === 'close') {
    isReady = false;
    connectedSince = null;
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }

    if (intentionalClose) {
      intentionalClose = false; // pausa/logout manual -- no auto-reconectar
      return;
    }

    const statusCode = lastDisconnect?.error?.output?.statusCode;
    const loggedOut  = statusCode === DisconnectReason.loggedOut;

    if (loggedOut) {
      logger.warn('[bot] Sesión cerrada desde el teléfono — generando QR nuevo');
      wipeAuthDir();
      currentQR = null;
      reconnectAttempts = 0;
      setDbStatus('disconnected');
      _connect().catch(e => logger.error({ err: e.message }, '[bot] error regenerando QR tras logout'));
      return;
    }

    setDbStatus('connecting');
    scheduleReconnect();
  }
}

function scheduleReconnect() {
  if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
    if (!reconnectExhausted) {
      reconnectExhausted = true;
      logger.error(
        { attempts: reconnectAttempts },
        '[bot] reintentos de reconexión agotados — se requiere reinicio manual (POST /api/bot/resume)'
      );
    }
    return;
  }
  const backoffMs = Math.min(BASE_RECONNECT_MS * 2 ** reconnectAttempts, MAX_RECONNECT_MS);
  reconnectAttempts += 1;
  logger.warn({ attempt: reconnectAttempts, backoffMs }, '[bot] reconectando');
  if (reconnectTimer) clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(() => _connect().catch(e => {
    logger.error({ err: e.message }, '[bot] reconexión err');
    scheduleReconnect();
  }), backoffMs);
}

async function _connect() {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  let version;
  try {
    ({ version } = await fetchLatestBaileysVersion());
  } catch (_) {
    version = [2, 3000, 1015901307]; // fallback si no hay internet al arrancar
  }

  sock = makeWASocket({
    version,
    auth: state,
    logger: baileysLogger,
    printQRInTerminal: false,
    browser: ['Concentrados Monserrath', 'Chrome', '1.0.0'],
    syncFullHistory: false,
    markOnlineOnConnect: false,
  });

  sock.ev.on('creds.update', saveCreds);
  sock.ev.on('connection.update', handleConnectionUpdate);
  sock.ev.on('messages.upsert', async ({ messages }) => {
    for (const msg of messages) {
      try { await handleInbound(msg); }
      catch (e) { logger.error({ err: e.message }, '[bot] handler err'); }
    }
  });
}

// ── API pública ───────────────────────────────────────────────
async function initBot() {
  if (process.env.BOT_ENABLED !== 'true') {
    logger.warn('[bot] BOT_ENABLED != true — bot desactivado');
    return;
  }
  const cfg = getBotConfigRow();
  if (!cfg.phone_encrypted) {
    logger.warn('[bot] Sin número configurado — esperando configuración desde el panel (POST /api/bot/configure)');
    return;
  }
  if (cfg.paused) {
    logger.info('[bot] Bot en pausa — usa POST /api/bot/resume para reconectar');
    return;
  }
  logger.info('[bot] Iniciando con baileys…');
  reconnectAttempts  = 0;
  reconnectExhausted = false;
  cleanupOldMedia();
  if (!mediaCleanupInterval) {
    mediaCleanupInterval = setInterval(cleanupOldMedia, 24 * 3_600_000).unref();
  }
  await _connect();
}

async function logoutBot() {
  intentionalClose = true;
  if (sock) {
    try { await sock.logout(); } catch (_) {}
    try { sock.end(undefined); } catch (_) {}
    sock = null;
  }
  wipeAuthDir();
  isReady = false;
  currentQR = null;
  connectedSince = null;
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
}

// Guarda/cambia el número (encriptado) y (re)inicia la conexión. Si ya había
// un número distinto vinculado, cierra sesión y limpia credenciales antes --
// WhatsApp ata la sesión al teléfono que escaneó el QR, no se puede "renombrar".
async function configurePhone(newPhone) {
  const digits = String(newPhone || '').replace(/\D/g, '');
  if (digits.length < 10) throw new Error('Número inválido — incluye indicativo de país');

  const cfg = getBotConfigRow();
  if (cfg.phone_encrypted) await logoutBot();

  const encrypted = encryptPhone(digits);
  getDB().prepare(
    `UPDATE bot_config SET phone_encrypted = ?, status = 'disconnected', paused = 0,
     updated_at = (datetime('now','localtime')) WHERE id = 1`
  ).run(encrypted);

  await initBot();
  return { changed: !!cfg.phone_encrypted };
}

async function pauseBot() {
  intentionalClose = true;
  if (sock) { try { sock.end(undefined); } catch (_) {} sock = null; }
  isReady = false;
  connectedSince = null;
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
  getDB().prepare(
    `UPDATE bot_config SET paused = 1, status = 'paused', updated_at = (datetime('now','localtime')) WHERE id = 1`
  ).run();
  logger.info('[bot] Pausado por admin');
}

async function resumeBot() {
  const cfg = getBotConfigRow();
  if (!cfg.phone_encrypted) throw new Error('No hay número configurado — configura uno primero');
  getDB().prepare(
    `UPDATE bot_config SET paused = 0, status = 'disconnected', updated_at = (datetime('now','localtime')) WHERE id = 1`
  ).run();
  logger.info('[bot] Reanudando…');
  reconnectAttempts  = 0;
  reconnectExhausted = false;
  await _connect();
}

function getStatus() {
  const cutoff = Date.now() - 3_600_000;
  const cfg = getBotConfigRow();
  let phoneMasked = null;
  if (cfg.phone_encrypted) {
    try {
      const p = decryptPhone(cfg.phone_encrypted);
      phoneMasked = `+${p.slice(0, 2)} ***${p.slice(-4)}`;
    } catch (_) {}
  }
  return {
    ready: isReady,
    hasQR: currentQR !== null,
    status: cfg.status,
    paused: !!cfg.paused,
    phone: phoneMasked,
    connectedSince,
    lastMessageAt,
    reconnectAttempts,
    maxReconnectAttempts: MAX_RECONNECT_ATTEMPTS,
    reconnectExhausted,
    sentLastHour: sentTimestamps.filter(t => t > cutoff).length,
    maxMsgsPerHour: MAX_MSGS_PER_HOUR,
  };
}

function getQR() { return currentQR; }

module.exports = {
  initBot, getStatus, getQR, configurePhone, pauseBot, resumeBot, logoutBot,
  cleanupOldMedia, canSendMore, MEDIA_DIR, DOCS_DIR,
};
