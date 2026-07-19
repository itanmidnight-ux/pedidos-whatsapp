'use strict';
const express = require('express');
const router  = express.Router();
const path    = require('path');
const { getDB } = require('../db/database');
const { productImages } = require('./products');
const { USE_S3 } = require('../utils/storage');

// Catalogo publico de solo lectura para el sitio publico (server/src/public-site)
// -- sin auth a proposito, pero solo expone campos seguros de cara al
// publico. Nunca no_fiado/favorite/aliases (uso interno del bot/dashboard).
function toPublicProduct(p) {
  return {
    id: p.id,
    name: p.name,
    price: p.price,
    category: p.category || 'Otros',
    description: p.description || '',
    sku: p.sku || null,
    in_stock: p.available === 1 && (p.stock === null || p.stock > 0),
    images: p.image_filenames ? p.image_filenames.split(',') : [],
  };
}

router.get('/products', async (req, res, next) => {
  try {
    const db = getDB();
    const { rows } = await db.query(`
      SELECT p.*, string_agg(pi.filename, ',') AS image_filenames
      FROM products p
      LEFT JOIN product_images pi ON pi.product_id = p.id
      WHERE p.available = 1
      GROUP BY p.id
      ORDER BY p.category ASC, p.name ASC
    `);
    res.json(rows.map(toPublicProduct));
  } catch (e) { next(e); }
});

router.get('/products/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
    const db = getDB();
    const { rows } = await db.query(`
      SELECT p.*, string_agg(pi.filename, ',') AS image_filenames
      FROM products p
      LEFT JOIN product_images pi ON pi.product_id = p.id
      WHERE p.id = $1 AND p.available = 1
      GROUP BY p.id
    `, [id]);
    if (!rows[0]) return res.status(404).json({ error: 'Producto no encontrado' });
    res.json(toPublicProduct(rows[0]));
  } catch (e) { next(e); }
});

// Imagenes de producto sin auth -- necesarias para que el sitio publico
// (sin login) pueda mostrar fotos reales en el catalogo y la ficha.
router.get('/products/images/:filename', async (req, res, next) => {
  try {
    const filename = path.basename(req.params.filename);
    if (!(await productImages.exists(filename))) return res.status(404).json({ error: 'No encontrado' });
    if (USE_S3) return res.send(await productImages.read(filename));
    res.sendFile(productImages.localPath(filename));
  } catch (e) { next(e); }
});

module.exports = router;
