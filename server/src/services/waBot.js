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
  Browsers
} = require('@whiskeysockets/baileys');
const pino = require('pino');

// ── Config ────────────────────────────────────────────────────
const AUTH_DIR  = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot', 'auth');
const MEDIA_DIR = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot', 'media');
const PHONE     = (process.env.BOT_PHONE || '').replace(/\D/g, '');
const API_URL   = `http://localhost:${process.env.PORT || 3000}`;
const API_KEY   = process.env.API_KEY;
const logger    = pino({ level: 'silent' });

[AUTH_DIR, MEDIA_DIR].forEach(d => { if (!fs.existsSync(d)) fs.mkdirSync(d, { recursive: true }); });

let sock           = null;
let retryCount     = 0;
let pairingDone    = false;
let heartbeatTimer = null;
let pollTimer      = null;
let isReady        = false;

const MAX_RETRIES  = 10;
const HEARTBEAT_MS = 25000;
const POLL_MS      = 3000;

const http = axios.create({ baseURL: API_URL, timeout: 15000, headers: { 'X-API-Key': API_KEY } });

// ── Helpers ───────────────────────────────────────────────────
function delay(ms) { return new Promise(r => setTimeout(r, ms)); }

function clearTimers() {
  if (heartbeatTimer) { clearInterval(heartbeatTimer); heartbeatTimer = null; }
  if (pollTimer)      { clearInterval(pollTimer);      pollTimer = null; }
}

async function postInbound(phone, name, message, mediaType, mediaUrl, profilePicUrl) {
  try {
    await http.post('/api/webhook/message', {
      phone, name, message,
      media_type:      mediaType   || undefined,
      media_url:       mediaUrl    || undefined,
      profile_pic_url: profilePicUrl || undefined,
      timestamp:       Date.now(),
    });
  } catch (e) {
    if (e.response?.status !== 429) console.error('[bot] webhook err', e.message);
  }
}

async function getProfilePic(jid) {
  try { return await sock.profilePictureUrl(jid, 'image'); }
  catch { return null; }
}

async function pollOutbound() {
  try {
    const { data } = await http.get('/api/messages/outbound/pending');
    for (const msg of (data.messages || [])) {
      try {
        const jid = `${msg.phone.replace(/\D/g, '')}@s.whatsapp.net`;

        if (msg.media_url) {
          const filePath = path.join(MEDIA_DIR, msg.media_url);
          if (fs.existsSync(filePath)) {
            const buffer = fs.readFileSync(filePath);
            if (msg.media_type === 'image') {
              await sock.sendMessage(jid, { image: buffer, caption: '' });
            } else if (msg.media_type === 'audio') {
              await sock.sendMessage(jid, {
                audio: buffer,
                mimetype: 'audio/mp4',
                ptt: true,
              });
            }
          }
        } else {
          await sock.sendMessage(jid, { text: msg.content });
        }

        await http.put(`/api/messages/${msg.id}/sent`);
        await delay(2000 + Math.random() * 3000);
      } catch (e) {
        console.error('[bot] send err', msg.id, e.message);
      }
    }
  } catch (_) {}
}

async function getProductMenu() {
  try {
    const { data } = await http.get('/api/products');
    const list = (data.products || data || [])
      .map((p, i) => `${i + 1}. ${p.name} — $${Number(p.price).toLocaleString('es-CO')}`)
      .join('\n');
    return `🐾 *Concentrados Monserrath*\n\n${list}\n\nEscríbenos tu pedido y te atendemos.`;
  } catch { return '🐾 *Concentrados Monserrath*\nEscríbenos tu pedido y te atendemos.'; }
}

// ── Connect ───────────────────────────────────────────────────
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
      isReady    = true;
      retryCount = 0;
      pairingDone = true;
      clearTimers();
      heartbeatTimer = setInterval(() => sock.sendPresenceUpdate('available').catch(() => {}), HEARTBEAT_MS);
      pollTimer      = setInterval(pollOutbound, POLL_MS);
    }

    if (connection === 'close') {
      isReady = false;
      clearTimers();
      const FATAL = [DisconnectReason.loggedOut, DisconnectReason.forbidden, DisconnectReason.badSession, 411];
      if (FATAL.includes(code)) {
        console.error(`[bot] ❌ Fatal disconnect (${code}). Limpiando sesión y reconectando...`);
        try {
          const files = fs.readdirSync(AUTH_DIR);
          for (const f of files) fs.unlinkSync(path.join(AUTH_DIR, f));
        } catch (_) {}
        pairingDone = false;
        retryCount  = 0;
        setTimeout(connect, 8000);
        return;
      }
      if (retryCount >= MAX_RETRIES) {
        console.error('[bot] ❌ Max retries alcanzados. Reiniciando ciclo de autenticación...');
        try {
          const files = fs.readdirSync(AUTH_DIR);
          for (const f of files) fs.unlinkSync(path.join(AUTH_DIR, f));
        } catch (_) {}
        pairingDone = false;
        retryCount  = 0;
        setTimeout(connect, 15000);
        return;
      }
      const backoff = code === DisconnectReason.restartRequired ? 500 : Math.min(1000 * 2 ** retryCount, 30000);
      retryCount++;
      console.log(`[bot] Reconectando en ${backoff}ms (${retryCount}/${MAX_RETRIES})…`);
      setTimeout(connect, backoff);
    }
  });

  // ── Inbound messages ──────────────────────────────────────
  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;
    for (const msg of messages) {
      if (msg.key.fromMe || !msg.message) continue;
      const jid = msg.key.remoteJid || '';
      if (jid.endsWith('@g.us') || jid.endsWith('@broadcast')) continue;

      const phone = jid.split('@')[0];
      const name  = msg.pushName || phone;

      // Fetch profile pic (non-blocking, best-effort)
      const picUrl = await getProfilePic(jid).catch(() => null);

      // ── Audio message ──────────────────────────────────
      if (msg.message.audioMessage) {
        try {
          const buffer   = await downloadMediaMessage(msg, 'buffer', {}, { logger, reuploadRequest: sock.updateMediaMessage });
          const filename = `${phone}_${Date.now()}.ogg`;
          fs.writeFileSync(path.join(MEDIA_DIR, filename), buffer);
          await postInbound(phone, name, '[Audio]', 'audio', filename, picUrl);
        } catch (e) { console.error('[bot] audio dl err', e.message); }
        continue;
      }

      // ── Image message ──────────────────────────────────
      if (msg.message.imageMessage) {
        try {
          const buffer   = await downloadMediaMessage(msg, 'buffer', {}, { logger, reuploadRequest: sock.updateMediaMessage });
          const filename = `${phone}_${Date.now()}.jpg`;
          fs.writeFileSync(path.join(MEDIA_DIR, filename), buffer);
          await postInbound(phone, name, '[Imagen]', 'image', filename, picUrl);
        } catch (e) { console.error('[bot] image dl err', e.message); }
        continue;
      }

      // ── Text message ───────────────────────────────────
      const text = (
        msg.message.conversation ||
        msg.message.extendedTextMessage?.text || ''
      ).trim();
      if (!text) continue;

      const lower = text.toLowerCase();
      if (/^(hola|menu|productos|cat[aá]logo|buenos|buenas)/.test(lower)) {
        const menu = await getProductMenu();
        await sock.sendMessage(jid, { text: menu });
        continue;
      }

      await postInbound(phone, name, text, null, null, picUrl);
    }
  });
}

// ── Public API ────────────────────────────────────────────────
async function initBot() {
  if (!PHONE) { console.warn('[bot] BOT_PHONE not set — bot disabled'); return; }
  console.log('[bot] Starting…');
  await connect();
}

function getStatus() {
  return { ready: isReady, retries: retryCount, phone: PHONE ? `***${PHONE.slice(-4)}` : null };
}

module.exports = { initBot, getStatus };
