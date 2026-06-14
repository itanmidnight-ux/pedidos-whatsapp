'use strict';
require('dotenv').config();
const path   = require('path');
const fs     = require('fs');
const axios  = require('axios');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
  downloadMediaMessage,
  Browsers,
} = require('@whiskeysockets/baileys');
const pino = require('pino');

// ── Directorios ───────────────────────────────────────────────
const BOT_DIR   = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot');
const AUTH_DIR  = path.join(BOT_DIR, 'auth');
const MEDIA_DIR = path.join(BOT_DIR, 'media');
const DOCS_DIR  = path.join(BOT_DIR, 'docs');
for (const d of [AUTH_DIR, MEDIA_DIR, DOCS_DIR]) fs.mkdirSync(d, { recursive: true });

// ── Config ────────────────────────────────────────────────────
const PHONE    = (process.env.BOT_PHONE || '').replace(/\D/g, '');
const API_URL  = `http://localhost:${process.env.PORT || 3000}`;
const API_KEY  = process.env.API_KEY;
const logger   = pino({ level: 'silent' });

let sock               = null;
let retryCount         = 0;
let pairingDone        = false;
let heartbeatTimer     = null;
let pollTimer          = null;
let isReady            = false;
let wasEverConnected   = false;

const MAX_RETRIES  = 10;
const HEARTBEAT_MS = 25000;
const POLL_MS      = 3000;

const http = axios.create({
  baseURL: API_URL,
  timeout: 15000,
  headers: { 'X-API-Key': API_KEY },
});

// ── Utilidades ────────────────────────────────────────────────
const delay = ms => new Promise(r => setTimeout(r, ms));

function clearTimers() {
  if (heartbeatTimer) { clearInterval(heartbeatTimer); heartbeatTimer = null; }
  if (pollTimer)      { clearInterval(pollTimer);      pollTimer = null; }
}

function normalizePhone(phone) {
  const d = String(phone).replace(/\D/g, '');
  if (d.length === 10 && d.startsWith('3')) return '57' + d;
  return d;
}

async function getProfilePic(jid) {
  try { return await sock.profilePictureUrl(jid, 'image'); } catch { return null; }
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
  } catch (e) {
    if (e.response?.status !== 429) console.error('[bot] webhook err', e.message);
  }
}

// ── Descargar y guardar media ──────────────────────────────────
async function downloadMedia(msg, ext, destDir = MEDIA_DIR) {
  const buffer   = await downloadMediaMessage(
    msg, 'buffer', {},
    { logger, reuploadRequest: sock.updateMediaMessage }
  );
  const filename = `${msg.key.remoteJid.split('@')[0]}_${Date.now()}.${ext}`;
  fs.writeFileSync(path.join(destDir, filename), buffer);
  return filename;
}

// ── Poll mensajes salientes ────────────────────────────────────
async function pollOutbound() {
  if (!isReady || !sock) return;
  try {
    const { data } = await http.get('/api/messages/outbound/pending');
    for (const msg of (data.messages || [])) {
      try {
        const jid = `${normalizePhone(msg.phone)}@s.whatsapp.net`;

        if (msg.media_url) {
          // Buscar archivo en media o docs
          const inMedia = path.join(MEDIA_DIR, msg.media_url);
          const inDocs  = path.join(DOCS_DIR,  msg.media_url);
          const fpath   = fs.existsSync(inMedia) ? inMedia
                        : fs.existsSync(inDocs)  ? inDocs
                        : null;

          if (fpath) {
            const buf = fs.readFileSync(fpath);
            switch (msg.media_type) {
              case 'image':
                await sock.sendMessage(jid, { image: buf, caption: msg.caption || '' });
                break;
              case 'video':
                await sock.sendMessage(jid, { video: buf, caption: msg.caption || '' });
                break;
              case 'audio':
              case 'voice': {
                const ext  = path.extname(msg.media_url).slice(1).toLowerCase();
                const mime = ext === 'ogg'  ? 'audio/ogg; codecs=opus'
                           : ext === 'mp3'  ? 'audio/mpeg'
                           : ext === 'aac'  ? 'audio/aac'
                           : 'audio/mp4';
                await sock.sendMessage(jid, { audio: buf, mimetype: mime, ptt: true });
                break;
              }
              case 'document': {
                await sock.sendMessage(jid, {
                  document: buf,
                  fileName: path.basename(msg.media_url),
                  mimetype: 'application/octet-stream',
                });
                break;
              }
            }
          }
        } else {
          await sock.sendMessage(jid, { text: msg.content });
        }

        await http.put(`/api/messages/${msg.id}/sent`);
        await delay(1500 + Math.random() * 2000);
      } catch (e) { console.error('[bot] send err', msg.id, e.message); }
    }
  } catch (_) {}
}

// ── Manejar mensajes entrantes ────────────────────────────────
async function handleInbound(msg) {
  if (msg.key.fromMe || !msg.message) return;
  const jid = msg.key.remoteJid || '';
  if (jid.endsWith('@g.us') || jid.endsWith('@broadcast')) return;

  const phone = jid.split('@')[0];
  const name  = msg.pushName || phone;
  const m     = msg.message;

  const picUrl = await getProfilePic(jid).catch(() => null);

  // ── AUDIO / Nota de voz ───────────────────────────────────
  if (m.audioMessage || m.pttMessage) {
    try {
      const isPtt = !!(m.pttMessage || m.audioMessage?.ptt);
      const fname = await downloadMedia(msg, isPtt ? 'ogg' : 'mp4');
      await postInbound(phone, name, isPtt ? '[Nota de voz]' : '[Audio]', 'audio', fname, picUrl);
      await delay(1000);
      await sock.sendMessage(jid, { text: '✅ Audio recibido. Un colaborador lo atenderá pronto.' });
    } catch (e) { console.error('[bot] audio err', e.message); }
    return;
  }

  // ── IMAGEN ────────────────────────────────────────────────
  if (m.imageMessage) {
    try {
      const fname   = await downloadMedia(msg, 'jpg');
      const caption = m.imageMessage.caption || '[Imagen]';
      await postInbound(phone, name, caption, 'image', fname, picUrl);
      await delay(1000);
      await sock.sendMessage(jid, { text: '✅ Imagen recibida. Un colaborador la revisará pronto.' });
    } catch (e) { console.error('[bot] image err', e.message); }
    return;
  }

  // ── VIDEO ─────────────────────────────────────────────────
  if (m.videoMessage) {
    try {
      const fname   = await downloadMedia(msg, 'mp4');
      const caption = m.videoMessage.caption || '[Video]';
      await postInbound(phone, name, caption, 'video', fname, picUrl);
      await delay(1000);
      await sock.sendMessage(jid, { text: '✅ Video recibido. Un colaborador lo revisará pronto.' });
    } catch (e) { console.error('[bot] video err', e.message); }
    return;
  }

  // ── DOCUMENTO ─────────────────────────────────────────────
  if (m.documentMessage) {
    try {
      const origName = m.documentMessage.fileName || 'documento';
      const ext      = origName.includes('.') ? origName.split('.').pop() : 'bin';
      const fname    = await downloadMedia(msg, ext, DOCS_DIR);
      await postInbound(phone, name, `[Documento: ${origName}]`, 'document', fname, picUrl);
      await delay(1000);
      await sock.sendMessage(jid, { text: '✅ Documento recibido. Un colaborador lo revisará.' });
    } catch (e) { console.error('[bot] doc err', e.message); }
    return;
  }

  // ── STICKER ───────────────────────────────────────────────
  if (m.stickerMessage) {
    try {
      const fname = await downloadMedia(msg, 'webp');
      await postInbound(phone, name, '[Sticker]', 'image', fname, picUrl);
    } catch (_) {}
    return;
  }

  // ── UBICACIÓN ─────────────────────────────────────────────
  if (m.locationMessage) {
    const { degreesLatitude: lat, degreesLongitude: lng, name: locName } = m.locationMessage;
    const label   = locName || `${String(lat).slice(0, 9)}, ${String(lng).slice(0, 9)}`;
    const mapsUrl = `https://maps.google.com/?q=${lat},${lng}`;
    await postInbound(phone, name, `📍 Ubicación compartida: ${label}\n${mapsUrl}`, null, null, picUrl);
    return;
  }

  // ── REACCIÓN ──────────────────────────────────────────────
  if (m.reactionMessage) {
    await postInbound(phone, name, `[Reacción: ${m.reactionMessage.text || '❤️'}]`, null, null, picUrl);
    return;
  }

  // ── TEXTO ─────────────────────────────────────────────────
  const text = (
    m.conversation ||
    m.extendedTextMessage?.text ||
    m.ephemeralMessage?.message?.conversation ||
    m.viewOnceMessage?.message?.conversation ||
    ''
  ).trim();
  if (!text) return;

  // Mostrar "escribiendo..." mientras procesa
  const typingMs = 800 + Math.min(text.length * 18, 2500);
  await sendTyping(jid, typingMs);
  await postInbound(phone, name, text, null, null, picUrl);
}

// ── Conectar ──────────────────────────────────────────────────
async function connect() {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();

  sock = makeWASocket({
    version,
    logger,
    auth: {
      creds: state.creds,
      keys: makeCacheableSignalKeyStore(state.keys, logger),
    },
    browser: Browsers.macOS('Safari'),
    generateHighQualityLinkPreview: false,
    keepAliveIntervalMs: 15000,
    connectTimeoutMs: 60000,
    defaultQueryTimeoutMs: 60000,
    retryRequestDelayMs: 250,
    markOnlineOnConnect: true,
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', async ({ connection, lastDisconnect }) => {
    const code = lastDisconnect?.error?.output?.statusCode;

    if (connection === 'connecting' && PHONE && !pairingDone && !state.creds.registered) {
      await delay(1500);
      try {
        const pair = await sock.requestPairingCode(PHONE);
        console.log(`\n[bot] Pairing code: ${pair.match(/.{1,4}/g).join('-')}\n`);
        pairingDone = true;
      } catch (e) { console.error('[bot] pairing err', e.message); }
    }

    if (connection === 'open') {
      console.log('[bot] ✅ Connected');
      isReady          = true;
      wasEverConnected = true;
      retryCount       = 0;
      pairingDone      = true;
      clearTimers();
      heartbeatTimer = setInterval(
        () => sock.sendPresenceUpdate('available').catch(() => {}),
        HEARTBEAT_MS
      );
      pollTimer = setInterval(pollOutbound, POLL_MS);
    }

    if (connection === 'close') {
      isReady = false;
      clearTimers();

      // loggedOut (401) only fatal if we were actually connected before;
      // during initial pairing WA sends 401 — must retry without clearing session
      const FATAL = [
        DisconnectReason.forbidden,
        DisconnectReason.badSession,
        411,
        ...(wasEverConnected ? [DisconnectReason.loggedOut] : []),
      ];

      if (FATAL.includes(code)) {
        console.error(`[bot] ❌ Fatal disconnect (${code}). Clearing session and restarting...`);
        _clearAuth();
        pairingDone      = false;
        wasEverConnected = false;
        retryCount       = 0;
        setTimeout(connect, 8000);
        return;
      }

      if (retryCount >= MAX_RETRIES) {
        console.error('[bot] ❌ Max retries reached. Clearing session and restarting...');
        _clearAuth();
        pairingDone      = false;
        wasEverConnected = false;
        retryCount       = 0;
        setTimeout(connect, 15000);
        return;
      }

      const immediate = code === DisconnectReason.restartRequired;
      const backoff   = immediate ? 500 : Math.min(1000 * 2 ** retryCount, 30000);
      retryCount++;
      console.log(`[bot] Reconnecting in ${backoff}ms (attempt ${retryCount}/${MAX_RETRIES})…`);
      setTimeout(connect, backoff);
    }
  });

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;
    for (const msg of messages) {
      try { await handleInbound(msg); }
      catch (e) { console.error('[bot] handler err', e.message); }
    }
  });
}

function _clearAuth() {
  try {
    for (const f of fs.readdirSync(AUTH_DIR)) fs.unlinkSync(path.join(AUTH_DIR, f));
  } catch (_) {}
}

// ── API pública ────────────────────────────────────────────────
async function initBot() {
  if (!PHONE) { console.warn('[bot] BOT_PHONE not set — bot disabled'); return; }
  console.log('[bot] Starting…');
  await connect();
}

function getStatus() {
  return {
    ready:   isReady,
    retries: retryCount,
    phone:   PHONE ? `+${PHONE.slice(0, 2)} ***${PHONE.slice(-4)}` : null,
  };
}

module.exports = { initBot, getStatus };
