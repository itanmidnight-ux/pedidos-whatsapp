'use strict';
require('dotenv').config();
const path  = require('path');
const fs    = require('fs');
const os    = require('os');
const crypto = require('crypto');
const { execFile } = require('child_process');
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
const { getDB, withTransaction, createListenClient } = require('../db/database');
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
let listenClient       = null; // conexion LISTEN/NOTIFY dedicada (ver setupOutboundListener)
let listenRetryTimer   = null;

// Con LISTEN/NOTIFY (ver setupOutboundListener) el bot se entera de
// mensajes salientes nuevos casi al instante -- este intervalo ya es solo
// la red de seguridad por si la suscripcion se cae, no el camino principal
// como antes (que era de 3s fijos).
const POLL_MS = 15_000;

// ── Reconexión con backoff exponencial ─────────────────────────
const BASE_RECONNECT_MS = 10_000;
const MAX_RECONNECT_MS  = 5 * 60_000;
const MAX_RECONNECT_ATTEMPTS = parseInt(process.env.BOT_MAX_RECONNECT_ATTEMPTS, 10) || 10;
let reconnectAttempts  = 0;
let reconnectExhausted = false;

// ── Salud / métricas para el panel de admin ────────────────────
let connectedSince = null;
let lastMessageAt  = null;

// ── Dedup de mensajes entrantes ──────────────────────────────────
// WhatsApp multi-device a veces reenvia el MISMO mensaje del cliente por
// mas de una ruta casi al mismo tiempo (ej. cuando el cliente tiene otro
// dispositivo vinculado) -- sin esto el bot procesaba cada copia por
// separado: contestaba dos veces y, si una copia llegaba resuelta por
// numero real y la otra por @lid crudo, hasta creaba un chat duplicado.
// El id de mensaje de WhatsApp se mantiene igual entre esas copias.
const recentMsgIds = new Map(); // msg.key.id -> timestamp
const MSG_DEDUP_WINDOW_MS = 2 * 60_000;
setInterval(() => {
  const cutoff = Date.now() - MSG_DEDUP_WINDOW_MS;
  for (const [id, t] of recentMsgIds) if (t < cutoff) recentMsgIds.delete(id);
}, 60_000).unref();

function isDuplicateMessage(msgId) {
  if (!msgId) return false;
  if (recentMsgIds.has(msgId)) return true;
  recentMsgIds.set(msgId, Date.now());
  return false;
}

// ── Cache de foto de perfil ────────────────────────────────────
// Antes se pedia a WhatsApp en CADA mensaje entrante (una llamada de red
// por mensaje) -- la foto de perfil no cambia a cada rato, cachear unas
// horas evita esa latencia extra y el riesgo de rate-limit por volumen.
const PROFILE_PIC_TTL_MS = 6 * 60 * 60_000;
const profilePicCache = new Map(); // jid -> { url, fetchedAt }

async function getProfilePicCached(jid) {
  const cached = profilePicCache.get(jid);
  if (cached && Date.now() - cached.fetchedAt < PROFILE_PIC_TTL_MS) return cached.url;
  let url = null;
  try { url = await sock.profilePictureUrl(jid, 'image'); } catch (_) {}
  profilePicCache.set(jid, { url, fetchedAt: Date.now() });
  return url;
}

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

// WhatsApp solo renderiza la burbuja de "nota de voz" (ptt) para audio real
// en ogg/opus -- cualquier otro contenedor sube bien pero el destinatario
// no puede reproducirlo ("este audio no esta disponible"). Se convierte
// siempre a ogg/opus mono 16kHz (mismos parametros que usa el propio
// WhatsApp) para que toda nota de voz -- venga grabada en Android, en Web,
// o subida como archivo -- se vea y suene igual que una nativa.
async function convertToOggOpus(buffer, srcExt) {
  const tmpIn  = path.join(os.tmpdir(), `wa-audio-in-${crypto.randomUUID()}.${srcExt || 'bin'}`);
  const tmpOut = path.join(os.tmpdir(), `wa-audio-out-${crypto.randomUUID()}.ogg`);
  try {
    fs.writeFileSync(tmpIn, buffer);
    await new Promise((resolve, reject) => {
      execFile('ffmpeg', [
        '-y', '-i', tmpIn,
        '-c:a', 'libopus', '-ar', '16000', '-ac', '1', '-b:a', '32k', '-application', 'voip',
        tmpOut,
      ], { timeout: 15_000 }, (err) => err ? reject(err) : resolve());
    });
    return fs.readFileSync(tmpOut);
  } catch (e) {
    logger.warn({ err: e.message }, '[bot] no se pudo convertir audio a ogg/opus -- se envia sin ptt');
    return null;
  } finally {
    for (const f of [tmpIn, tmpOut]) { try { fs.unlinkSync(f); } catch (_) {} }
  }
}

// ── bot_config (Postgres) ─────────────────────────────────────────
async function getBotConfigRow() {
  const { rows } = await getDB().query('SELECT * FROM bot_config WHERE id = 1');
  return rows[0];
}

async function setDbStatus(status) {
  await getDB().query(
    `UPDATE bot_config SET status = $1, updated_at = now_iso() WHERE id = 1`, [status]
  );
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

async function postInbound(jid, phone, name, message, mediaType, mediaUrl, profilePicUrl) {
  try {
    const body = {
      phone, name, message, jid,
      media_type:      mediaType    || undefined,
      media_url:       mediaUrl     || undefined,
      profile_pic_url: profilePicUrl || undefined,
      timestamp:       new Date().toISOString(),
    };
    const ts = Date.now();
    const signature = crypto.createHmac('sha256', process.env.WEBHOOK_SECRET || '')
      .update(JSON.stringify(body) + ':' + ts).digest('hex');
    await http.post('/api/webhook/message', body, {
      headers: { 'X-Baileys-Timestamp': String(ts), 'X-Baileys-Signature': signature },
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

// ── LISTEN/NOTIFY: entrega casi instantanea de mensajes salientes ──────
// Complementa (no reemplaza) el polling de mas abajo -- si Postgres o la
// suscripcion fallan, el bot sigue funcionando igual, solo que con la
// latencia del polling periodico (ver POLL_MS) en vez de instantanea.
async function setupOutboundListener() {
  if (listenClient) return;
  try {
    const client = createListenClient();
    await client.connect();
    await client.query('LISTEN outbound_message');
    client.on('notification', () => {
      pollOutbound().catch(e => logger.error({ err: e.message }, '[bot] pollOutbound (notify) err'));
    });
    client.on('error', (err) => {
      logger.warn({ err: err.message }, '[bot] listener de mensajes salientes se cayo -- sigue funcionando solo con polling periodico');
      listenClient = null;
      scheduleListenerRetry();
    });
    listenClient = client;
    logger.info('[bot] escuchando mensajes salientes nuevos en tiempo real (Postgres LISTEN)');
  } catch (e) {
    logger.warn({ err: e.message }, '[bot] no se pudo activar LISTEN -- el bot sigue funcionando solo con polling periodico');
    listenClient = null;
    scheduleListenerRetry();
  }
}

function scheduleListenerRetry() {
  if (listenRetryTimer) return;
  listenRetryTimer = setTimeout(() => {
    listenRetryTimer = null;
    if (isReady) setupOutboundListener().catch(() => {});
  }, 30_000).unref();
}

function teardownOutboundListener() {
  if (listenRetryTimer) { clearTimeout(listenRetryTimer); listenRetryTimer = null; }
  if (listenClient) {
    try { listenClient.end(); } catch (_) {}
    listenClient = null;
  }
}

// ── Poll mensajes salientes ────────────────────────────────────
async function pollOutbound() {
  if (!isReady || !sock) return;
  try {
    // Bot y server viven en el mismo proceso -- antes esto era un
    // GET HTTP a si mismo cada POLL_MS (3s), agregando latencia de
    // red+JSON innecesaria a CADA ciclo, tenga o no mensajes pendientes.
    const { rows: messages } = await getDB().query(`
      SELECT m.*, c.wa_jid AS wa_jid
      FROM messages m
      LEFT JOIN customers c ON c.phone = m.phone
      WHERE m.direction='outbound' AND m.sent=0
      ORDER BY m.created_at ASC
    `);
    for (const msg of messages) {
      if (!canSendMore()) {
        const now = Date.now();
        if (now - lastCapWarnAt > 5 * 60_000) {
          lastCapWarnAt = now;
          logger.warn({ max: MAX_MSGS_PER_HOUR }, '[bot] límite de mensajes/hora alcanzado — pausando envíos');
        }
        break;
      }
      try {
        const jid = msg.wa_jid || toJid(msg.phone);

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
                // ptt:true (nota de voz) solo es valido con ogg/opus real --
                // cualquier otro contenedor sube "bien" pero el destinatario
                // no puede reproducirlo ("este audio no esta disponible").
                // Se convierte siempre a ogg/opus con ffmpeg para que se
                // vea y suene como una nota de voz nativa sin importar el
                // origen (Android, Web, o archivo subido). Si la conversion
                // falla por algun motivo, se manda como audio normal en vez
                // de dejarlo sin enviar -- degradacion segura, nunca rompe.
                const converted = ext === 'ogg' ? null : await convertToOggOpus(buffer, ext);
                if (converted) {
                  await sock.sendMessage(jid, { audio: converted, mimetype: 'audio/ogg; codecs=opus', ptt: true });
                } else {
                  const mimetype = ext === 'ogg'  ? 'audio/ogg; codecs=opus'
                                 : ext === 'mp3'  ? 'audio/mpeg'
                                 : ext === 'aac'  ? 'audio/aac'
                                 : ext === 'weba' ? 'audio/webm; codecs=opus'
                                 : 'audio/mp4';
                  await sock.sendMessage(jid, { audio: buffer, mimetype, ptt: ext === 'ogg' });
                }
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

        await getDB().query('UPDATE messages SET sent=1 WHERE id=$1', [msg.id]);
        sentTimestamps.push(Date.now());
        lastMessageAt = new Date().toISOString();
        await delay(1500 + Math.random() * 2000);
      } catch (e) { logger.error({ err: e.message, orderId: msg.id }, '[bot] send err'); }
    }
  } catch (_) {}
}

// Antes del fix de sender_pn, un contacto @lid quedaba guardado con su
// numero interno en vez del real -- eso crea un cliente/chat duplicado
// del mismo contacto. En cuanto identificamos su numero real, se fusiona
// todo (mensajes, pedidos, pendientes) bajo el numero correcto y se borra
// el duplicado viejo.
async function mergeStaleLidCustomer(rawJid, realPhone) {
  if (!rawJid.endsWith('@lid')) return;
  const stalePhone = jidNormalizedUser(rawJid).split('@')[0];
  if (!stalePhone || stalePhone === realPhone) return;
  const db = getDB();
  const { rows: staleRows } = await db.query('SELECT * FROM customers WHERE phone=$1', [stalePhone]);
  const stale = staleRows[0];
  if (!stale) return;
  const { rows: realRows } = await db.query('SELECT * FROM customers WHERE phone=$1', [realPhone]);
  const real = realRows[0];

  await withTransaction(async (client) => {
    await client.query('UPDATE messages SET phone=$1 WHERE phone=$2', [realPhone, stalePhone]);

    const { rows: staleHasPending } = await client.query('SELECT 1 FROM pending_orders WHERE phone=$1', [stalePhone]);
    if (staleHasPending[0]) {
      const { rows: realHasPending } = await client.query('SELECT 1 FROM pending_orders WHERE phone=$1', [realPhone]);
      if (realHasPending[0]) {
        await client.query('DELETE FROM pending_orders WHERE phone=$1', [stalePhone]);
      } else {
        await client.query('UPDATE pending_orders SET phone=$1 WHERE phone=$2', [realPhone, stalePhone]);
      }
    }

    if (real) {
      await client.query('UPDATE orders SET customer_id=$1 WHERE customer_id=$2', [real.id, stale.id]);
      await client.query('UPDATE customers SET name=COALESCE(name,$1), profile_pic_url=COALESCE(profile_pic_url,$2) WHERE id=$3',
        [stale.name, stale.profile_pic_url, real.id]);
      await client.query('DELETE FROM customers WHERE id=$1', [stale.id]);
    } else {
      await client.query('UPDATE customers SET phone=$1 WHERE id=$2', [realPhone, stale.id]);
    }
  });

  logger.info({ from: stalePhone, to: realPhone }, '[bot] fusionado chat duplicado @lid con numero real');
}

// ── Manejar mensajes entrantes ────────────────────────────────
async function handleInbound(msg) {
  if (msg.key.fromMe) return;
  if (isDuplicateMessage(msg.key.id)) return;
  const rawJid = msg.key.remoteJid || '';
  if (!rawJid || rawJid.endsWith('@g.us') || rawJid === 'status@broadcast') return;

  // WhatsApp identifica cada vez mas contactos por @lid (privacidad/multi-
  // device) en vez del numero real. Cuando eso pasa, el propio stanza trae
  // aparte el numero real en sender_pn -- si esta, usarlo siempre: da el
  // telefono correcto para mostrar Y un JID @s.whatsapp.net que si se puede
  // responder (a un @lid reconstruido a mano nunca le llega nada).
  const jid     = msg.key.senderPn ? jidNormalizedUser(msg.key.senderPn) : jidNormalizedUser(rawJid);
  const phone   = jid.split('@')[0];
  if (msg.key.senderPn) {
    try { await mergeStaleLidCustomer(rawJid, phone); } catch (e) { logger.error({ err: e.message }, '[bot] merge lid err'); }
  }
  const name    = msg.pushName || phone;

  const profilePicUrl = await getProfilePicCached(jid);

  const content = unwrapMessage(msg.message);
  if (!content) return;
  const type = Object.keys(content)[0];

  // ── AUDIO / NOTA DE VOZ ──────────────────────────────────
  if (type === 'audioMessage') {
    try {
      const isPtt = !!content.audioMessage.ptt;
      const fname = await downloadAndSave(msg, phone, isPtt ? 'ogg' : 'mp4');
      await postInbound(jid, phone, name, isPtt ? '[Nota de voz]' : '[Audio]', 'audio', fname, profilePicUrl);
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
      await postInbound(jid, phone, name, caption, 'image', fname, profilePicUrl);
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
      await postInbound(jid, phone, name, caption, 'video', fname, profilePicUrl);
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
      await postInbound(jid, phone, name, `[Documento: ${origName}]`, 'document', fname, profilePicUrl);
      await delay(1000);
      await sock.sendMessage(jid, { text: '✅ Documento recibido. Un colaborador lo revisará.' });
    } catch (e) { logger.error({ err: e.message }, '[bot] doc err'); }
    return;
  }

  // ── STICKER ──────────────────────────────────────────────
  if (type === 'stickerMessage') {
    try {
      const fname = await downloadAndSave(msg, phone, 'webp');
      await postInbound(jid, phone, name, '[Sticker]', 'image', fname, profilePicUrl);
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
    await postInbound(jid, phone, name, `📍 Ubicación: ${label}\n${mapsUrl}`, null, null, profilePicUrl);
    return;
  }

  // ── REACCIÓN ─────────────────────────────────────────────
  if (type === 'reactionMessage') {
    await postInbound(jid, phone, name, `[Reacción: ${content.reactionMessage.text || '❤️'}]`, null, null, profilePicUrl);
    return;
  }

  // ── TEXTO ────────────────────────────────────────────────
  const text = (content.conversation || content.extendedTextMessage?.text || '').trim();
  if (!text) return;
  const typingMs = 800 + Math.min(text.length * 18, 2500);
  await sendTyping(jid, typingMs);
  await postInbound(jid, phone, name, text, null, null, profilePicUrl);
}

// ── Conexión / eventos baileys ──────────────────────────────────
async function handleConnectionUpdate(update) {
  const { connection, lastDisconnect, qr } = update;

  if (qr) {
    try {
      currentQR = await QRCode.toDataURL(qr);
      await setDbStatus('qr_pending');
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
    await setDbStatus('connected');
    logger.info('[bot] Conectado y listo');
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(pollOutbound, POLL_MS);
    setupOutboundListener().catch(() => {});
    pollOutbound().catch(() => {}); // drena lo que se haya acumulado mientras estaba desconectado
  }

  if (connection === 'close') {
    isReady = false;
    connectedSince = null;
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
    teardownOutboundListener();

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
      await setDbStatus('disconnected');
      _connect().catch(e => logger.error({ err: e.message }, '[bot] error regenerando QR tras logout'));
      return;
    }

    await setDbStatus('connecting');
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
      // La alerta por WhatsApp queda encolada y se envia apenas el bot
      // vuelva a conectar (degradacion aceptable -- sin WhatsApp activo no
      // hay otro canal para avisar de inmediato) -- SIEMPRE queda visible
      // igual en el panel de alertas del dashboard sin depender del bot.
      try { require('../utils/securityAlert').raiseAlert('bot_disconnected', `Bot de WhatsApp perdió la sesión tras ${reconnectAttempts} reintentos — requiere reinicio manual`); }
      catch (e) { logger.error({ err: e.message }, '[bot] error registrando alerta de desconexion'); }
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
    browser: ['Supermercado GO', 'Chrome', '1.0.0'],
    syncFullHistory: false,
    markOnlineOnConnect: false,
  });

  sock.ev.on('creds.update', saveCreds);
  sock.ev.on('connection.update', handleConnectionUpdate);
  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    // 'notify' = mensaje nuevo de verdad. 'append'/otros = resync de
    // historial que WhatsApp reenvia en cada reconexion -- sin este filtro
    // se reprocesan mensajes viejos como si fueran nuevos y el bot vuelve
    // a contestar (a veces varias veces) cosas que ya habia respondido.
    if (type !== 'notify') return;
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
  const cfg = await getBotConfigRow();
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
  teardownOutboundListener();
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
}

// Guarda/cambia el número (encriptado) y (re)inicia la conexión. Si ya había
// un número distinto vinculado, cierra sesión y limpia credenciales antes --
// WhatsApp ata la sesión al teléfono que escaneó el QR, no se puede "renombrar".
async function configurePhone(newPhone) {
  const digits = String(newPhone || '').replace(/\D/g, '');
  if (digits.length < 10) throw new Error('Número inválido — incluye indicativo de país');

  const cfg = await getBotConfigRow();
  if (cfg.phone_encrypted) await logoutBot();

  const encrypted = encryptPhone(digits);
  await getDB().query(
    `UPDATE bot_config SET phone_encrypted = $1, status = 'disconnected', paused = 0,
     updated_at = now_iso() WHERE id = 1`, [encrypted]
  );

  await initBot();
  return { changed: !!cfg.phone_encrypted };
}

async function pauseBot() {
  intentionalClose = true;
  if (sock) { try { sock.end(undefined); } catch (_) {} sock = null; }
  isReady = false;
  connectedSince = null;
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
  teardownOutboundListener();
  if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
  await getDB().query(
    `UPDATE bot_config SET paused = 1, status = 'paused', updated_at = now_iso() WHERE id = 1`
  );
  logger.info('[bot] Pausado por admin');
}

async function resumeBot() {
  const cfg = await getBotConfigRow();
  if (!cfg.phone_encrypted) throw new Error('No hay número configurado — configura uno primero');
  await getDB().query(
    `UPDATE bot_config SET paused = 0, status = 'disconnected', updated_at = now_iso() WHERE id = 1`
  );
  logger.info('[bot] Reanudando…');
  reconnectAttempts  = 0;
  reconnectExhausted = false;
  await _connect();
}

async function getStatus() {
  const cutoff = Date.now() - 3_600_000;
  const cfg = await getBotConfigRow();
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
    botEnabled: process.env.BOT_ENABLED === 'true',
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
