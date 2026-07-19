'use strict';
const { getPool } = require('./db');

// Metadata visual por categoria -- usada para el placeholder de producto
// (emoji + color) cuando aun no hay foto real subida desde el panel admin.
const CATEGORY_META = {
  'Frutas y Verduras':  { emoji: '🍎', color: '#3f8f3f' },
  'Carnes y Pollo':     { emoji: '🥩', color: '#b9433f' },
  'Lácteos y Huevos':   { emoji: '🥛', color: '#c9a227' },
  'Panadería':          { emoji: '🍞', color: '#b5762a' },
  'Abarrotes':          { emoji: '🛒', color: '#3766b5' },
  'Bebidas':            { emoji: '🥤', color: '#1f9aa3' },
  'Aseo del Hogar':     { emoji: '🧽', color: '#2f8f7a' },
  'Cuidado Personal':   { emoji: '🧴', color: '#b5548f' },
  'Mascotas':           { emoji: '🐾', color: '#7a54b5' },
  'Congelados':         { emoji: '❄️', color: '#3f6fb5' },
  'Otros':              { emoji: '📦', color: '#6b6b6b' },
};
const CATEGORY_ORDER = Object.keys(CATEGORY_META);

function categoryMeta(name) {
  return CATEGORY_META[name] || CATEGORY_META['Otros'];
}

function withMeta(p) {
  return {
    ...p,
    meta: categoryMeta(p.category),
    in_stock: p.available === 1 && (p.stock === null || p.stock === undefined || p.stock > 0),
  };
}

async function listCategories() {
  const pool = getPool();
  const { rows } = await pool.query(`
    SELECT category, COUNT(*) AS total
    FROM products
    WHERE available = 1
    GROUP BY category
  `);
  const counts = new Map(rows.map(r => [r.category || 'Otros', Number(r.total)]));
  return CATEGORY_ORDER
    .filter(c => counts.has(c))
    .map(c => ({ name: c, total: counts.get(c), meta: categoryMeta(c) }));
}

async function listProducts({ category, q } = {}) {
  const pool = getPool();
  let sql = `
    SELECT p.*, string_agg(pi.filename, ',') AS image_filenames
    FROM products p
    LEFT JOIN product_images pi ON pi.product_id = p.id
    WHERE p.available = 1
  `;
  const params = [];
  if (category) { params.push(category); sql += ` AND p.category = $${params.length}`; }
  if (q)        { params.push(`%${q}%`);  sql += ` AND p.name ILIKE $${params.length}`; }
  sql += ' GROUP BY p.id ORDER BY p.name ASC';
  const { rows } = await pool.query(sql, params);
  return rows.map(p => withMeta({
    ...p,
    images: p.image_filenames ? p.image_filenames.split(',') : [],
  }));
}

async function getProduct(id) {
  const pool = getPool();
  const { rows } = await pool.query(`
    SELECT p.*, string_agg(pi.filename, ',') AS image_filenames
    FROM products p
    LEFT JOIN product_images pi ON pi.product_id = p.id
    WHERE p.id = $1 AND p.available = 1
    GROUP BY p.id
  `, [id]);
  const p = rows[0];
  if (!p) return null;
  return withMeta({ ...p, images: p.image_filenames ? p.image_filenames.split(',') : [] });
}

module.exports = { listCategories, listProducts, getProduct, categoryMeta, CATEGORY_ORDER };
