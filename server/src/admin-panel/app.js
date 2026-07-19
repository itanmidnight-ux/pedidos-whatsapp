'use strict';
const express = require('express');
const helmet  = require('helmet');
const rateLimit = require('express-rate-limit');
const multer  = require('multer');
const path    = require('path');
const { parseCookies, setCookie, clearCookie } = require('./cookies');
const { requireAdmin, verifyCsrf, newCsrfToken } = require('./auth');
const { apiRequest, fetchImage } = require('./apiClient');

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 5 * 1024 * 1024 } });

const app = express();
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(helmet());
app.use('/static', express.static(path.join(__dirname, 'public'), { maxAge: '1h' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

// Rate-limit propio, mas estricto que el de la API principal -- este puerto
// solo lo usa un admin humano desde localhost/VPN, nunca trafico masivo.
app.use(rateLimit({ windowMs: 60_000, max: 60, standardHeaders: true, legacyHeaders: false }));

function render(req, res, view, locals = {}) {
  res.render(view, { csrf: parseCookies(req).csrf || '', adminUser: req.adminUser || null, ...locals });
}

app.get('/health', (req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));

// ── Login ────────────────────────────────────────────────────
app.get('/login', (req, res) => {
  if (parseCookies(req).token) return res.redirect('/productos');
  render(req, res, 'login', { error: null });
});

app.post('/login', async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) return render(req, res, 'login', { error: 'Usuario y contraseña requeridos' });
  const { ok, data } = await apiRequest(null, 'POST', '/api/auth/token', { json: { username, password } });
  if (!ok || !data?.token) return render(req, res, 'login', { error: data?.error || 'Credenciales incorrectas' });
  if (data.role !== 'admin') return render(req, res, 'login', { error: 'Esta cuenta no tiene permisos de administrador' });
  setCookie(res, 'token', data.token, { maxAgeMs: 30 * 24 * 60 * 60 * 1000 });
  setCookie(res, 'csrf', newCsrfToken(), { maxAgeMs: 30 * 24 * 60 * 60 * 1000, httpOnly: false });
  res.redirect('/productos');
});

app.post('/logout', requireAdmin, verifyCsrf, async (req, res) => {
  await apiRequest(req.adminToken, 'POST', '/api/auth/logout');
  clearCookie(res, 'token');
  clearCookie(res, 'csrf');
  res.redirect('/login');
});

// ── Todo lo de abajo requiere sesion admin ─────────────────────
app.use(requireAdmin);

app.get('/', (req, res) => res.redirect('/productos'));

app.get('/productos', async (req, res) => {
  const { ok, data } = await apiRequest(req.adminToken, 'GET', '/api/products');
  render(req, res, 'productos-lista', { products: ok && Array.isArray(data) ? data : [], error: ok ? null : 'No se pudo cargar el catálogo.' });
});

app.get('/productos/nuevo', (req, res) => {
  render(req, res, 'productos-form', { product: null, error: null });
});

app.post('/productos/nuevo', verifyCsrf, async (req, res) => {
  const body = formToProductBody(req.body);
  const { ok, data } = await apiRequest(req.adminToken, 'POST', '/api/products', { json: body });
  if (!ok) return render(req, res, 'productos-form', { product: body, error: data?.error || 'No se pudo crear el producto.' });
  res.redirect(`/productos/${data.id}`);
});

app.get('/productos/:id', async (req, res) => {
  const { ok, data } = await apiRequest(req.adminToken, 'GET', '/api/products');
  const product = ok && Array.isArray(data) ? data.find(p => p.id === parseInt(req.params.id, 10)) : null;
  if (!product) { res.status(404); return render(req, res, '404'); }
  render(req, res, 'productos-form', { product, error: null });
});

app.post('/productos/:id', verifyCsrf, async (req, res) => {
  const id = parseInt(req.params.id, 10);
  const body = formToProductBody(req.body);
  const { ok, data } = await apiRequest(req.adminToken, 'PUT', `/api/products/${id}`, { json: body });
  if (!ok) return render(req, res, 'productos-form', { product: { ...body, id }, error: data?.error || 'No se pudo guardar.' });
  res.redirect(`/productos/${id}`);
});

app.post('/productos/:id/eliminar', verifyCsrf, async (req, res) => {
  await apiRequest(req.adminToken, 'DELETE', `/api/products/${req.params.id}`);
  res.redirect('/productos');
});

app.post('/productos/:id/imagenes', upload.single('image'), async (req, res) => {
  const id = req.params.id;
  // El CSRF de este form va como campo normal (multer ya parseo multipart)
  const cookieCsrf = parseCookies(req).csrf;
  if (!req.body._csrf || req.body._csrf !== cookieCsrf) return res.status(403).send('Token de seguridad inválido.');
  if (req.file) {
    const form = new FormData();
    form.append('image', new Blob([req.file.buffer], { type: req.file.mimetype }), req.file.originalname);
    await apiRequest(req.adminToken, 'POST', `/api/products/${id}/images`, { form });
  }
  res.redirect(`/productos/${id}`);
});

app.post('/productos/:id/imagenes/:filename/eliminar', verifyCsrf, async (req, res) => {
  await apiRequest(req.adminToken, 'DELETE', `/api/products/${req.params.id}/images/${encodeURIComponent(req.params.filename)}`);
  res.redirect(`/productos/${req.params.id}`);
});

// Proxy de imagenes -- el admin panel no guarda imagenes propias, solo
// reenvia la del server principal (mismo archivo en disco), adjuntando el
// token de la cookie porque esa ruta SI exige auth en la API real.
app.get('/img/:filename', async (req, res) => {
  const upstream = await fetchImage(req.adminToken, req.params.filename);
  if (!upstream.ok) return res.status(upstream.status).end();
  res.setHeader('Content-Type', upstream.headers.get('content-type') || 'image/jpeg');
  const buf = Buffer.from(await upstream.arrayBuffer());
  res.send(buf);
});

function formToProductBody(body) {
  const out = {
    name: (body.name || '').trim(),
    price: body.price !== undefined && body.price !== '' ? Number(body.price) : undefined,
    category: body.category || null,
    description: body.description || null,
    sku: body.sku || null,
    stock: body.stock !== undefined && body.stock !== '' ? Number(body.stock) : null,
    available: body.available === 'on' ? 1 : 0,
    favorite: body.favorite === 'on' ? 1 : 0,
    no_fiado: body.no_fiado === 'on' ? 1 : 0,
  };
  Object.keys(out).forEach(k => out[k] === undefined && delete out[k]);
  return out;
}

app.use((req, res) => { res.status(404); render(req, res, '404'); });

module.exports = app;
