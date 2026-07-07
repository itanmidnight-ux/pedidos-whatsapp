'use strict';
require('dotenv').config();
const path = require('path');
const fs   = require('fs');
const axios = require('axios');
const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const logger = require('../utils/logger');

// ── Directorios ───────────────────────────────────────────────
const BOT_DIR   = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot');
const AUTH_DIR  = path.join(BOT_DIR, 'wwebjs-auth');
const MEDIA_DIR = path.join(BOT_DIR, 'media');
const DOCS_DIR  = path.join(BOT_DIR, 'docs');
for (const d of [AUTH_DIR, MEDIA_DIR, DOCS_DIR]) fs.mkdirSync(d, { recursive: true });

// ── Config ────────────────────────────────────────────────────
const PHONE   = (process.env.BOT_PHONE || '').replace(/\D/g, '');
const API_URL = `http://localhost:${process.env.PORT || 3000}`;
const API_KEY = process.env.API_KEY;

let client     = null;
let isReady    = false;
let pollTimer  = null;
let currentQR  = null;   // stored as data-URL for admin endpoint
let reconnectTimer = null;
let mediaCleanupInterval = null;

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
  return `${normalizePhone(phone)}@c.us`;
}

async function sendTyping(chatId, durationMs = 1500) {
  try {
    const chat = await client.getChatById(chatId);
    await chat.sendStateTyping();
    await delay(durationMs);
    await chat.clearState();
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

// ── Descargar y guardar media ──────────────────────────────────
async function downloadAndSave(msg, ext, destDir = MEDIA_DIR) {
  const media = await msg.downloadMedia();
  if (!media) throw new Error('No media data');
  const buffer   = Buffer.from(media.data, 'base64');
  const filename = `${msg.from.split('@')[0]}_${Date.now()}.${ext}`;
  fs.writeFileSync(path.join(destDir, filename), buffer);
  return filename;
}

// ── Poll mensajes salientes ────────────────────────────────────
async function pollOutbound() {
  if (!isReady || !client) return;
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
        const to = toJid(msg.phone);

        if (msg.media_url) {
          const inMedia = path.join(MEDIA_DIR, msg.media_url);
          const inDocs  = path.join(DOCS_DIR,  msg.media_url);
          const fpath   = fs.existsSync(inMedia) ? inMedia
                        : fs.existsSync(inDocs)  ? inDocs
                        : null;

          if (fpath) {
            const b64  = fs.readFileSync(fpath).toString('base64');
            const ext  = path.extname(msg.media_url).slice(1).toLowerCase();

            let mime, sendOpts = {};
            switch (msg.media_type) {
              case 'image':
                mime = ext === 'png' ? 'image/png' : 'image/jpeg';
                sendOpts = { caption: msg.caption || '' };
                break;
              case 'video':
                mime = 'video/mp4';
                sendOpts = { caption: msg.caption || '' };
                break;
              case 'audio':
              case 'voice':
                mime = ext === 'ogg' ? 'audio/ogg; codecs=opus'
                     : ext === 'mp3' ? 'audio/mpeg'
                     : ext === 'aac' ? 'audio/aac'
                     : 'audio/mp4';
                sendOpts = { sendAudioAsVoice: true };
                break;
              default:
                mime = 'application/octet-stream';
                break;
            }
            const media = new MessageMedia(mime, b64, path.basename(msg.media_url));
            await client.sendMessage(to, media, sendOpts);
          }
        } else {
          await client.sendMessage(to, msg.content);
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
  if (msg.fromMe) return;
  const from = msg.from || '';
  if (from.endsWith('@g.us') || from.endsWith('@broadcast')) return;

  const phone   = from.split('@')[0];
  const contact = await msg.getContact().catch(() => null);
  const name    = contact?.pushname || contact?.name || phone;

  let profilePicUrl = null;
  try { profilePicUrl = await client.getProfilePicUrl(from); } catch (_) {}

  const t = msg.type;

  // ── AUDIO / PTT ──────────────────────────────────────────
  if (t === 'audio' || t === 'ptt') {
    try {
      const fname = await downloadAndSave(msg, t === 'ptt' ? 'ogg' : 'mp4');
      await postInbound(phone, name, t === 'ptt' ? '[Nota de voz]' : '[Audio]', 'audio', fname, profilePicUrl);
      await delay(1000);
      await client.sendMessage(from, '✅ Audio recibido. Un colaborador lo atenderá pronto.');
    } catch (e) { logger.error({ err: e.message }, '[bot] audio err'); }
    return;
  }

  // ── IMAGEN ───────────────────────────────────────────────
  if (t === 'image') {
    try {
      const fname   = await downloadAndSave(msg, 'jpg');
      const caption = msg.body || '[Imagen]';
      await postInbound(phone, name, caption, 'image', fname, profilePicUrl);
      await delay(1000);
      await client.sendMessage(from, '✅ Imagen recibida. Un colaborador la revisará pronto.');
    } catch (e) { logger.error({ err: e.message }, '[bot] image err'); }
    return;
  }

  // ── VIDEO ────────────────────────────────────────────────
  if (t === 'video') {
    try {
      const fname   = await downloadAndSave(msg, 'mp4');
      const caption = msg.body || '[Video]';
      await postInbound(phone, name, caption, 'video', fname, profilePicUrl);
      await delay(1000);
      await client.sendMessage(from, '✅ Video recibido. Un colaborador lo revisará pronto.');
    } catch (e) { logger.error({ err: e.message }, '[bot] video err'); }
    return;
  }

  // ── DOCUMENTO ────────────────────────────────────────────
  if (t === 'document') {
    try {
      const origName = msg.filename || 'documento';
      const ext      = origName.includes('.') ? origName.split('.').pop() : 'bin';
      const fname    = await downloadAndSave(msg, ext, DOCS_DIR);
      await postInbound(phone, name, `[Documento: ${origName}]`, 'document', fname, profilePicUrl);
      await delay(1000);
      await client.sendMessage(from, '✅ Documento recibido. Un colaborador lo revisará.');
    } catch (e) { logger.error({ err: e.message }, '[bot] doc err'); }
    return;
  }

  // ── STICKER ──────────────────────────────────────────────
  if (t === 'sticker') {
    try {
      const fname = await downloadAndSave(msg, 'webp');
      await postInbound(phone, name, '[Sticker]', 'image', fname, profilePicUrl);
    } catch (_) {}
    return;
  }

  // ── UBICACIÓN ────────────────────────────────────────────
  if (t === 'location') {
    const loc     = msg.location || {};
    const lat     = loc.latitude;
    const lng     = loc.longitude;
    const locName = loc.description || '';
    const label   = locName || `${String(lat).slice(0, 9)}, ${String(lng).slice(0, 9)}`;
    const mapsUrl = `https://maps.google.com/?q=${lat},${lng}`;
    await postInbound(phone, name, `📍 Ubicación: ${label}\n${mapsUrl}`, null, null, profilePicUrl);
    return;
  }

  // ── REACCIÓN ─────────────────────────────────────────────
  if (t === 'reaction') {
    await postInbound(phone, name, `[Reacción: ${msg.reaction || '❤️'}]`, null, null, profilePicUrl);
    return;
  }

  // ── TEXTO ────────────────────────────────────────────────
  const text = (msg.body || '').trim();
  if (!text) return;
  const typingMs = 800 + Math.min(text.length * 18, 2500);
  await sendTyping(from, typingMs);
  await postInbound(phone, name, text, null, null, profilePicUrl);
}

// ── Crear/inicializar cliente ─────────────────────────────────
function _buildClient() {
  const c = new Client({
    authStrategy: new LocalAuth({
      clientId: 'monserrath-bot',
      dataPath:  AUTH_DIR,
    }),
    puppeteer: {
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-accelerated-2d-canvas',
        '--no-first-run',
        '--no-zygote',
        '--disable-gpu',
      ],
    },
  });

  c.on('qr', async (qr) => {
    // Vinculación siempre por código QR (WhatsApp → Dispositivos vinculados →
    // Vincular un dispositivo) -- no usar pairing code por número de teléfono.
    try {
      const QRCode = require('qrcode');
      currentQR = await QRCode.toDataURL(qr);
      logger.info('[bot] QR listo — GET /api/bot/qr');
    } catch (e) {
      currentQR = null;
      logger.error({ err: e.message }, '[bot] No se pudo generar el QR');
    }
  });

  c.on('authenticated', () => {
    currentQR = null;
    logger.info('[bot] Autenticado — sesión guardada');
  });

  c.on('auth_failure', (msg) => {
    logger.error({ msg }, '[bot] Fallo de autenticación');
    currentQR = null;
  });

  c.on('ready', () => {
    logger.info('[bot] Conectado y listo');
    isReady   = true;
    currentQR = null;
    connectedSince    = new Date().toISOString();
    reconnectAttempts  = 0;
    reconnectExhausted = false;
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(pollOutbound, POLL_MS);
  });

  c.on('disconnected', (reason) => {
    logger.warn({ reason }, '[bot] Desconectado');
    isReady = false;
    connectedSince = null;
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
    scheduleReconnect();
  });

  c.on('message', async (msg) => {
    try { await handleInbound(msg); }
    catch (e) { logger.error({ err: e.message }, '[bot] handler err'); }
  });

  return c;
}

function scheduleReconnect() {
  if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
    if (!reconnectExhausted) {
      reconnectExhausted = true;
      logger.error(
        { attempts: reconnectAttempts },
        '[bot] reintentos de reconexión agotados — se requiere reinicio manual (POST /api/bot/restart)'
      );
    }
    return;
  }
  const backoffMs = Math.min(BASE_RECONNECT_MS * 2 ** reconnectAttempts, MAX_RECONNECT_MS);
  reconnectAttempts += 1;
  logger.warn({ attempt: reconnectAttempts, backoffMs }, '[bot] reconectando');
  if (reconnectTimer) clearTimeout(reconnectTimer);
  reconnectTimer = setTimeout(_reconnect, backoffMs);
}

async function _reconnect() {
  try {
    if (client) { try { await client.destroy(); } catch (_) {} }
    client = _buildClient();
    await client.initialize();
  } catch (e) {
    logger.error({ err: e.message }, '[bot] reconexión err');
    scheduleReconnect();
  }
}

// ── API pública ───────────────────────────────────────────────
async function initBot() {
  if (!PHONE) { logger.warn('[bot] BOT_PHONE no configurado — bot desactivado'); return; }
  logger.info('[bot] Iniciando con whatsapp-web.js…');
  reconnectAttempts  = 0;
  reconnectExhausted = false;
  cleanupOldMedia();
  if (!mediaCleanupInterval) {
    mediaCleanupInterval = setInterval(cleanupOldMedia, 24 * 3_600_000).unref();
  }
  client = _buildClient();
  await client.initialize();
}

function getStatus() {
  const cutoff = Date.now() - 3_600_000;
  return {
    ready:  isReady,
    hasQR:  currentQR !== null,
    phone:  PHONE ? `+${PHONE.slice(0, 2)} ***${PHONE.slice(-4)}` : null,
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

module.exports = { initBot, getStatus, getQR, cleanupOldMedia, canSendMore, MEDIA_DIR, DOCS_DIR };
