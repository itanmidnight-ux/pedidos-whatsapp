'use strict';
const express = require('express');
const helmet  = require('helmet');
const compression = require('compression');
const path    = require('path');
const { listCategories, listProducts, getProduct } = require('./queries');
const { PRODUCT_IMAGES_DIR } = require('../routes/products');
const fs = require('fs');
const logger = require('../utils/logger');

const BRAND = {
  name: 'Supermercado GO',
  city: 'Cúcuta',
  tagline: 'Tu mercado de confianza en Cúcuta',
  phone: '300 123 4567',
  whatsapp: '573001234567',
  email: 'contacto@supermercadogo.com.co',
  address: 'Av. Gran Colombia, Cúcuta, Norte de Santander',
  hours: 'Lunes a Sábado 8:00am - 8:00pm, Domingos 8:00am - 2:00pm',
};

const app = express();
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(compression());
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc:   ["'self'", "'unsafe-inline'"],
      scriptSrc:  ["'self'"],
      imgSrc:     ["'self'", "data:"],
      connectSrc: ["'self'"],
    },
  },
}));
app.use('/static', express.static(path.join(__dirname, 'public'), { maxAge: '1d' }));
app.locals.BRAND = BRAND;
// URL publica de la app/dashboard existente (Flutter Web, /app) -- vive en
// otro host/puerto (deploy-linux.sh la fija a https://<CF_APP_HOST>/app/
// cuando se configura el named tunnel con dominio propio). Sin eso, cae a
// localhost:3000/app/ para desarrollo local.
app.locals.APP_PUBLIC_URL = process.env.APP_PUBLIC_URL || 'http://localhost:3000/app/';

// Imagenes reales de producto (subidas por el panel admin) -- misma carpeta
// que usa el server principal, servidas aqui sin auth porque el catalogo
// publico no requiere login.
app.get('/img/producto/:filename', (req, res) => {
  const fp = path.join(PRODUCT_IMAGES_DIR, path.basename(req.params.filename));
  if (!fs.existsSync(fp)) return res.status(404).end();
  res.sendFile(fp);
});

app.get('/health', (req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));

app.get('/', async (req, res, next) => {
  try {
    const categories = await listCategories();
    const destacados = (await listProducts()).slice(0, 8);
    res.render('home', { title: BRAND.name, categories, destacados });
  } catch (e) { next(e); }
});

app.get('/catalogo', async (req, res, next) => {
  try {
    const categories = await listCategories();
    const categoria = req.query.categoria || '';
    const q = (req.query.q || '').trim();
    const products = await listProducts({ category: categoria || undefined, q: q || undefined });
    res.render('catalogo', { title: `Catálogo — ${BRAND.name}`, categories, products, categoria, q });
  } catch (e) { next(e); }
});

app.get('/producto/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    const product = id ? await getProduct(id) : null;
    if (!product) return res.status(404).render('404', { title: 'Producto no encontrado' });
    res.render('producto', { title: `${product.name} — ${BRAND.name}`, product });
  } catch (e) { next(e); }
});

app.get('/nosotros', (req, res) => res.render('nosotros', { title: `Nosotros — ${BRAND.name}` }));
app.get('/contacto', (req, res) => res.render('contacto', { title: `Contacto — ${BRAND.name}` }));
app.get('/acceso', (req, res) => res.render('acceso', { title: `Acceso — ${BRAND.name}` }));

const POLICIES = {
  terminos:      { title: 'Términos y Condiciones', view: 'politicas/terminos' },
  privacidad:    { title: 'Política de Privacidad', view: 'politicas/privacidad' },
  devoluciones:  { title: 'Política de Devoluciones y Cambios', view: 'politicas/devoluciones' },
  envios:        { title: 'Política de Envíos', view: 'politicas/envios' },
};
app.get('/politicas/:slug', (req, res) => {
  const p = POLICIES[req.params.slug];
  if (!p) return res.status(404).render('404', { title: 'Página no encontrada' });
  res.render(p.view, { title: `${p.title} — ${BRAND.name}` });
});

app.use((req, res) => res.status(404).render('404', { title: 'Página no encontrada' }));

app.use((err, req, res, next) => {
  logger.error({ err: err.message }, '[public-site] error no manejado');
  res.status(500).render('404', { title: 'Error' });
});

module.exports = app;
