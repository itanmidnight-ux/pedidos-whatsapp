'use strict';
require('dotenv').config();
const path   = require('path');
const axios  = require('axios');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
  makeInMemoryStore,
  Browsers
} = require('@whiskeysockets/baileys');
const pino = require('pino');

// ── Config ────────────────────────────────────────────────────
const AUTH_DIR   = path.join(process.env.APPDATA || process.env.HOME, 'pedidos-bot', 'auth');
const PHONE      = (process.env.BOT_PHONE || '').replace(/\D/g, '');
const API_URL    = `http://localhost:${process.env.PORT || 3000}`;
const API_KEY    = process.env.API_KEY;
const logger     = pino({ level: 'silent' });

let sock            = null;
let retryCount      = 0;
let pairingDone     = false;
let heartbeatTimer  = null;
let pollTimer       = null;
let isReady         = false;

const MAX_RETRIES   = 10;
const HEARTBEAT_MS  = 25000;
const POLL_MS       = 3000;

// ── Internal HTTP helpers (no auth for local calls) ──────────
const http = axios.create({ baseURL: API_URL, timeout: 10000, headers: { 'X-API-Key': API_KEY } });

async function postInbound(phone, name, message) {
  try {
    await http.post('/api/webhook/message', { phone, name, message, timestamp: Date.now() });
  } catch (e) {
    if (e.response?.status !== 429) console.error('[bot] webhook err', e.message);
  }
}

async function pollOutbound() {
  try {
    const { data } = await http.get('/api/messages/outbound/pending');
    for (const msg of (data.messages || [])) {
      try {
        const jid = `${msg.phone.replace(/\D/g, '')}@s.whatsapp.net`;
        await sock.sendMessage(jid, { text: msg.content });
        await http.put(`/api/messages/${msg.id}/sent`);
        // anti-ban: jitter 2-5s between messages
        await delay(2000 + Math.random() * 3000);
      } catch (e) {
        console.error('[bot] send err', msg.id, e.message);
      }
    }
  } catch (_) {}
}

function delay(ms) { return new Promise(r => setTimeout(r, ms)); }

function clearTimers() {
  if (heartbeatTimer) { clearInterval(heartbeatTimer); heartbeatTimer = null; }
  if (pollTimer)      { clearInterval(pollTimer);      pollTimer = null; }
}

// ── Product menu ──────────────────────────────────────────────
async function getProductMenu() {
  try {
    const { data } = await http.get('/api/products');
    const list = (data.products || data || [])
      .map((p, i) => `${i + 1}. ${p.name} — $${Number(p.price).toLocaleString('es-CO')}`)
      .join('\n');
    return `🐾 *Concentrados Monserrath*\n\n${list}\n\nEscríbenos tu pedido y te atendemos.`;
  } catch { return '🐾 *Concentrados Monserrath*\nEscríbenos tu pedido y te atendemos.'; }
}

// ── Core connect ─────────────────────────────────────────────
async function connect() {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();

  sock = makeWASocket({
    version,
    logger,
    auth: {
      creds: state.creds,
      keys: makeCacheableSignalKeyStore(state.keys, logger)
    },
    browser: Browsers.macOS('Safari'),
    generateHighQualityLinkPreview: false,
    keepAliveIntervalMs: 15000,
    connectTimeoutMs: 60000,
    defaultQueryTimeoutMs: 60000,
    retryRequestDelayMs: 250,
    markOnlineOnConnect: true,
  });

  // ── Auth save ─────────────────────────────────────────────
  sock.ev.on('creds.update', saveCreds);

  // ── Connection lifecycle ──────────────────────────────────
  sock.ev.on('connection.update', async ({ connection, lastDisconnect, qr }) => {
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
      isReady = true;
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
        console.error(`[bot] ❌ Fatal disconnect (${code}). Delete ${AUTH_DIR} and restart.`);
        return;
      }

      if (retryCount >= MAX_RETRIES) {
        console.error('[bot] ❌ Max retries reached. Manual restart required.');
        return;
      }

      const immediate = code === DisconnectReason.restartRequired;
      const backoff   = immediate ? 500 : Math.min(1000 * 2 ** retryCount, 30000);
      retryCount++;
      console.log(`[bot] Reconnecting in ${backoff}ms (attempt ${retryCount}/${MAX_RETRIES})…`);
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
      const text  = (
        msg.message.conversation ||
        msg.message.extendedTextMessage?.text ||
        ''
      ).trim();
      if (!text) continue;

      const lower = text.toLowerCase();
      if (/^(hola|menu|productos|cat[aá]logo|buenos|buenas)/.test(lower)) {
        const menu = await getProductMenu();
        await sock.sendMessage(jid, { text: menu });
        continue;
      }

      await postInbound(phone, name, text);
    }
  });
}

// ── Public API ────────────────────────────────────────────────
async function initBot() {
  if (!PHONE) { console.warn('[bot] BOT_PHONE not set — bot disabled'); return; }
  console.log('[bot] Starting…');
  await connect();
}

function getStatus() { return { ready: isReady, retries: retryCount, phone: PHONE ? `***${PHONE.slice(-4)}` : null }; }

module.exports = { initBot, getStatus };
