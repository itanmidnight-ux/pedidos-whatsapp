'use strict';
require('dotenv').config();
const express = require('express');
const helmet  = require('helmet');
const cors    = require('cors');
const rateLimit = require('express-rate-limit');
const compression = require('compression');
const path    = require('path');
const logger = require('./utils/logger');
const pinoHttp = require('pino-http');

const app = express();

// Necesario cuando el servidor está detrás de un proxy (ngrok, nginx, etc.)
// Sin esto express-rate-limit lanza ERR_ERL_UNEXPECTED_X_FORWARDED_FOR
app.set('trust proxy', 1);
app.use(compression());

const { ipActivityMiddleware, startIpActivityFlusher } = require('./middleware/ipActivity');
app.use(ipActivityMiddleware);
if (process.env.NODE_ENV !== 'test') startIpActivityFlusher();

// ── Flutter web ANTES de helmet ──────────────────────────────
// CSP y los headers cross-origin quedan fuera de helmet aca a proposito:
// CanvasKit (el renderer de Flutter web) carga .wasm y Web Workers via
// blob: -- una CSP generica los bloquea, y COOP/COEP/CORP ya se fijan a
// mano abajo con los valores exactos que CanvasKit necesita. El resto de
// proteccion de helmet (HSTS, nosniff, X-Frame-Options, oculta
// X-Powered-By, etc.) si aplica: no afecta la carga de assets.
const appSecurityHeaders = helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
  crossOriginOpenerPolicy: false,
  crossOriginResourcePolicy: false,
});

app.use('/app', (req, res, next) => {
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Cross-Origin-Opener-Policy',   'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
  next();
}, appSecurityHeaders, express.static(path.join(__dirname, 'webapp')));

// ── Seguridad para el resto (API) ────────────────────────────
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc:  ["'self'"],
      scriptSrc:   ["'self'", "'unsafe-inline'"],
      styleSrc:    ["'self'", "'unsafe-inline'"],
      imgSrc:      ["'self'", "data:", "https:"],
      connectSrc:  ["'self'"],
      frameSrc:    ["'none'"],
      upgradeInsecureRequests: [],
    },
  },
  crossOriginEmbedderPolicy: false,
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true,
  },
}));

// ── CORS restrictivo ─────────────────────────────────────────
const allowedOrigins = [
  process.env.SERVER_DOMAIN  ? `https://${process.env.SERVER_DOMAIN}` : null,
  'https://tu-dominio.duckdns.org',
  'https://midominio.ts.net',
  'http://localhost:3000',
  'http://127.0.0.1:3000',
].filter(Boolean);

app.use(cors({
  origin: (origin, cb) => {
    if (!origin) return cb(null, true);
    if (allowedOrigins.includes(origin)) return cb(null, true);
    cb(new Error('Origen no permitido por CORS'));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-API-Key'],
}));

app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true, limit: '2mb' }));

// ── Rate limiting (desactivado en tests: no aporta nada y solo hace
// que los tests se pisen entre sí a través del contador compartido) ──
if (process.env.NODE_ENV !== 'test') {
  app.use('/api/', rateLimit({ windowMs: 60_000, max: 120, standardHeaders: true, legacyHeaders: false }));
  app.use('/api/auth', rateLimit({
    windowMs: 15 * 60_000, max: 10, standardHeaders: true, legacyHeaders: false,
    message: { error: 'Demasiados intentos. Espera 15 minutos.' },
  }));
  app.use('/api/webhook', rateLimit({ windowMs: 60_000, max: 60, standardHeaders: true, legacyHeaders: false }));
}

app.use('/api', pinoHttp({ logger }));

// ── Rutas API ─────────────────────────────────────────────────
app.use('/api/webhook',  require('./routes/webhook'));
app.use('/api/products', require('./routes/products'));
app.use('/api/orders',   require('./routes/orders'));
app.use('/api/auth',     require('./routes/auth'));
app.use('/api/messages', require('./routes/messages'));
app.use('/api/users',    require('./routes/users'));
app.use('/api/bot',      require('./routes/bot'));
app.use('/api/estados',  require('./routes/estados'));
app.use('/api/cart',     require('./routes/cart'));
app.use('/api/chat',     require('./routes/chat'));
app.use('/api/settings', require('./routes/settings'));
app.use('/api/analytics', require('./routes/analytics'));
app.use('/api/reports',  require('./routes/reports'));
app.use('/api/staff-locations', require('./routes/staffLocations'));
app.use('/api/payments', require('./routes/payments'));

app.get('/health',  (req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));
app.get('/preview', (req, res) => res.sendFile(path.join(__dirname, 'preview.html')));

// Raiz -> redirige a /app/
app.get('/', (req, res) => res.redirect(301, '/app/'));

// SPA fallback: /app/* sin archivo -> index.html (Flutter router)
app.get('/app/*', (req, res) => {
  const index = path.join(__dirname, 'webapp', 'index.html');
  if (require('fs').existsSync(index)) {
    res.sendFile(index);
  } else {
    res.status(503).send('App en construccion. API disponible en /api/');
  }
});

// ── Error handler global ──────────────────────────────────────
app.use((err, req, res, next) => {
  // multer LIMIT_FILE_SIZE / LIMIT_UNEXPECTED_FILE → 400 not 500
  const isMulterLimit = err.code && err.code.startsWith('LIMIT_');
  const status = err.status || (isMulterLimit ? 400 : 500);
  if (status >= 500) logger.error({ err: err.message, at: err.stack?.split('\n')[1] }, 'Error no manejado');
  res.status(status).json({
    error: status >= 500 ? 'Error interno del servidor' : (err.message || 'Error'),
  });
});

module.exports = app;
