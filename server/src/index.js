require('dotenv').config();
const express = require('express');
const helmet  = require('helmet');
const cors    = require('cors');
const rateLimit = require('express-rate-limit');
const path    = require('path');
const { initDB } = require('./db/database');
const { schedulePDFJob } = require('./services/pdfScheduler');

const app = express();

// Necesario cuando el servidor está detrás de un proxy (ngrok, nginx, etc.)
// Sin esto express-rate-limit lanza ERR_ERL_UNEXPECTED_X_FORWARDED_FOR
app.set('trust proxy', 1);

// ── Flutter web ANTES de helmet ──────────────────────────────
// Se sirve sin CSP ni CORP para que WASM y Workers carguen sin restricciones.
// Es código propio — no necesita CSP de protección.
app.use('/app', (req, res, next) => {
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('ngrok-skip-browser-warning', 'true');
  // Permitir workers cross-origin (necesario para skwasm)
  res.setHeader('Cross-Origin-Opener-Policy',   'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
  next();
}, express.static(path.join(__dirname, 'webapp')));

// ── Seguridad para el resto (API) ────────────────────────────
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc:  ["'self'", "'unsafe-inline'"],
      styleSrc:   ["'self'", "'unsafe-inline'"],
      imgSrc:     ["'self'", "data:"],
      connectSrc: ["'self'", "https://*.ngrok-free.dev"],
      frameSrc:   ["'none'"],
    },
  },
  crossOriginEmbedderPolicy: false,
}));

// ── CORS restrictivo ─────────────────────────────────────────
const allowedOrigins = [
  process.env.NGROK_URL,
  process.env.NGROK_DOMAIN   ? `https://${process.env.NGROK_DOMAIN}`   : null,
  process.env.SERVER_DOMAIN  ? `https://${process.env.SERVER_DOMAIN}`  : null,
  process.env.SERVER_DOMAIN  ? `http://${process.env.SERVER_DOMAIN}`   : null,
  'https://tu-dominio.duckdns.org',
  'http://tu-dominio.duckdns.org',
  'http://localhost:3000',
  'http://127.0.0.1:3000',
  'http://localhost:80',
  'http://127.0.0.1:80',
].filter(Boolean);

app.use(cors({
  origin: (origin, cb) => {
    if (!origin) return cb(null, true);
    if (allowedOrigins.some(o => origin.startsWith(o))) return cb(null, true);
    if (origin.endsWith('.ngrok-free.dev') || origin.endsWith('.ngrok.io')) return cb(null, true);
    if (origin.endsWith('.duckdns.org') || origin.endsWith('.trycloudflare.com')) return cb(null, true);
    cb(new Error('Origen no permitido por CORS'));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-API-Key', 'ngrok-skip-browser-warning'],
}));

app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true, limit: '2mb' }));

// ── Rate limiting ─────────────────────────────────────────────
app.use('/api/', rateLimit({ windowMs: 60_000, max: 120, standardHeaders: true, legacyHeaders: false }));
app.use('/api/auth', rateLimit({
  windowMs: 15 * 60_000, max: 10, standardHeaders: true, legacyHeaders: false,
  message: { error: 'Demasiados intentos. Espera 15 minutos.' },
}));
app.use('/api/webhook', rateLimit({ windowMs: 60_000, max: 60, standardHeaders: true, legacyHeaders: false }));

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
app.use('/api/settings', require('./routes/settings'));

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
  if (status >= 500) console.error('[ERROR]', err.message, err.stack?.split('\n')[1]);
  res.status(status).json({
    error: status >= 500 ? 'Error interno del servidor' : (err.message || 'Error'),
  });
});

const PORT = process.env.PORT || 3000;
initDB().then(() => {
  schedulePDFJob();
  app.listen(PORT, async () => {
    console.log(`Servidor corriendo en puerto ${PORT}`);
    if (process.env.BOT_ENABLED === 'true') {
      const { initBot } = require('./services/waBot');
      await initBot().catch(e => console.error('[bot] init error:', e.message));
    }
  });
}).catch(err => { console.error('Error iniciando servidor:', err); process.exit(1); });
