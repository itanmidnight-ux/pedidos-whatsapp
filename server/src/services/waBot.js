'use strict';
require('dotenv').config();
const path = require('path');
const fs   = require('fs');
const axios = require('axios');
const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');

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

const POLL_MS = 3000;

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
  } catch (e) {
    if (e.response?.status !== 429) console.error('[bot] webhook err', e.message);
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
        await delay(1500 + Math.random() * 2000);
      } catch (e) { console.error('[bot] send err', msg.id, e.message); }
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
    } catch (e) { console.error('[bot] audio err', e.message); }
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
    } catch (e) { console.error('[bot] image err', e.message); }
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
    } catch (e) { console.error('[bot] video err', e.message); }
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
    } catch (e) { console.error('[bot] doc err', e.message); }
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
    if (PHONE) {
      // Prefer phone-number pairing: user enters code in WA > Linked Devices > Link by phone
      try {
        const code = await c.requestPairingCode(PHONE);
        const fmt  = code.match(/.{1,4}/g)?.join('-') ?? code;
        console.log('[bot] ════════════════════════════════');
        console.log(`[bot] CÓDIGO DE VINCULACIÓN: ${fmt}`);
        console.log('[bot] WhatsApp → Dispositivos vinculados → Vincular con número de teléfono');
        console.log('[bot] ════════════════════════════════');
        currentQR = null;
        return;
      } catch (e) {
        console.log('[bot] Pairing code falló, usando QR fallback:', e.message);
      }
    }
    // Fallback: QR
    try {
      const QRCode = require('qrcode');
      currentQR = await QRCode.toDataURL(qr);
    } catch (_) { currentQR = null; }
    console.log('[bot] QR listo — GET /api/bot/qr');
  });

  c.on('authenticated', () => {
    currentQR = null;
    console.log('[bot] ✅ Autenticado — sesión guardada');
  });

  c.on('auth_failure', (msg) => {
    console.error('[bot] ❌ Fallo de autenticación:', msg);
    currentQR = null;
  });

  c.on('ready', () => {
    console.log('[bot] ✅ Conectado y listo');
    isReady   = true;
    currentQR = null;
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(pollOutbound, POLL_MS);
  });

  c.on('disconnected', (reason) => {
    console.log(`[bot] Desconectado (${reason}) — reconectando en 10s…`);
    isReady = false;
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
    if (reconnectTimer) clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(_reconnect, 10000);
  });

  c.on('message', async (msg) => {
    try { await handleInbound(msg); }
    catch (e) { console.error('[bot] handler err', e.message); }
  });

  return c;
}

async function _reconnect() {
  try {
    if (client) { try { await client.destroy(); } catch (_) {} }
    client = _buildClient();
    await client.initialize();
  } catch (e) {
    console.error('[bot] reconexión err:', e.message);
    if (reconnectTimer) clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(_reconnect, 15000);
  }
}

// ── API pública ───────────────────────────────────────────────
async function initBot() {
  if (!PHONE) { console.warn('[bot] BOT_PHONE no configurado — bot desactivado'); return; }
  console.log('[bot] Iniciando con whatsapp-web.js…');
  client = _buildClient();
  await client.initialize();
}

function getStatus() {
  return {
    ready:  isReady,
    hasQR:  currentQR !== null,
    phone:  PHONE ? `+${PHONE.slice(0, 2)} ***${PHONE.slice(-4)}` : null,
  };
}

function getQR() { return currentQR; }

module.exports = { initBot, getStatus, getQR };
