const express = require('express');
const router = express.Router();
const path   = require('path');
const fs     = require('fs');
const multer = require('multer');
const { jwtAuth, adminAuth, clientAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

const PRODUCT_IMAGES_DIR = path.join(process.env.APPDATA || process.env.HOME || process.env.USERPROFILE, 'pedidos-bot', 'product-images');
fs.mkdirSync(PRODUCT_IMAGES_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, PRODUCT_IMAGES_DIR),
  filename:    (req, file, cb) => cb(null, `${Date.now()}-${file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_')}`),
});
const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!file.mimetype.startsWith('image/'))
      return cb(Object.assign(new Error('Solo imágenes (jpg, png, webp, gif)'), { status: 400 }));
    cb(null, true);
  },
});

function validateProduct({ name, price, aliases }) {
  if (name !== undefined) {
    if (typeof name !== 'string' || name.trim().length === 0 || name.length > 200)
      return 'name debe ser texto de 1-200 caracteres';
  }
  if (price !== undefined) {
    if (typeof price !== 'number' || isNaN(price) || price < 0 || price > 100_000_000)
      return 'price debe ser número positivo menor a 100,000,000';
  }
  if (aliases !== undefined) {
    if (!Array.isArray(aliases) || aliases.length > 20)
      return 'aliases debe ser array de máximo 20 elementos';
    if (aliases.some(a => typeof a !== 'string' || a.length > 100))
      return 'cada alias debe ser texto de máximo 100 caracteres';
  }
  return null;
}

router.get('/', clientAuth, (req, res) => {
  const db = getDB();
  const products = db.prepare(`
    SELECT p.*, GROUP_CONCAT(pi.filename) AS image_filenames
    FROM products p
    LEFT JOIN product_images pi ON pi.product_id = p.id
    GROUP BY p.id
    ORDER BY p.favorite DESC, p.name ASC
  `).all();
  res.json(products.map(p => ({
    ...p,
    aliases: JSON.parse(p.aliases || '[]'),
    images: p.image_filenames ? p.image_filenames.split(',') : [],
    image_filenames: undefined,
  })));
});

router.post('/', adminAuth, (req, res) => {
  const { name, price, aliases } = req.body;
  if (!name || price == null) return res.status(400).json({ error: 'name y price requeridos' });
  const err = validateProduct({ name, price, aliases });
  if (err) return res.status(400).json({ error: err });
  const db = getDB();
  const result = db.prepare('INSERT INTO products (name, price, aliases) VALUES (?, ?, ?)')
    .run(name.trim(), price, JSON.stringify(aliases || []));
  const product = db.prepare('SELECT * FROM products WHERE id = ?').get(result.lastInsertRowid);
  res.json({ ...product, aliases: JSON.parse(product.aliases || '[]') });
});

router.put('/:id', adminAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const { name, price, aliases, available, favorite, no_fiado } = req.body;
  const err = validateProduct({ name, price, aliases });
  if (err) return res.status(400).json({ error: err });
  const db = getDB();
  db.prepare(`UPDATE products SET
    name      = COALESCE(?, name),
    price     = COALESCE(?, price),
    aliases   = COALESCE(?, aliases),
    available = COALESCE(?, available),
    favorite  = COALESCE(?, favorite),
    no_fiado  = COALESCE(?, no_fiado)
    WHERE id = ?`)
    .run(
      name   ? name.trim() : null,
      price  ?? null,
      aliases ? JSON.stringify(aliases) : null,
      available ?? null,
      favorite  ?? null,
      no_fiado  ?? null,
      id
    );
  const product = db.prepare('SELECT * FROM products WHERE id = ?').get(id);
  if (!product) return res.status(404).json({ error: 'No encontrado' });
  res.json({ ...product, aliases: JSON.parse(product.aliases || '[]') });
});

router.delete('/:id', adminAuth, (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!id || id <= 0) return res.status(400).json({ error: 'ID inválido' });
  const db = getDB();
  // Delete associated images from disk
  const imgs = db.prepare('SELECT filename FROM product_images WHERE product_id=?').all(id);
  imgs.forEach(img => {
    try { fs.unlinkSync(path.join(PRODUCT_IMAGES_DIR, img.filename)); } catch {}
  });
  db.prepare('DELETE FROM products WHERE id = ?').run(id);
  res.json({ success: true });
});

// POST /api/products/:id/images — upload product image (admin only)
router.post('/:id/images', adminAuth, upload.single('image'), (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (!req.file) return res.status(400).json({ error: 'No se recibió imagen' });
  const db = getDB();
  if (!db.prepare('SELECT id FROM products WHERE id=?').get(id))
    return res.status(404).json({ error: 'Producto no encontrado' });
  db.prepare('INSERT INTO product_images (product_id, filename) VALUES (?,?)').run(id, req.file.filename);
  res.status(201).json({ filename: req.file.filename });
});

// DELETE /api/products/:id/images/:filename — delete product image (admin only)
router.delete('/:id/images/:filename', adminAuth, (req, res) => {
  const { id, filename } = req.params;
  const db = getDB();
  const img = db.prepare('SELECT id FROM product_images WHERE product_id=? AND filename=?').get(id, filename);
  if (!img) return res.status(404).json({ error: 'Imagen no encontrada' });
  try { fs.unlinkSync(path.join(PRODUCT_IMAGES_DIR, filename)); } catch {}
  db.prepare('DELETE FROM product_images WHERE id=?').run(img.id);
  res.json({ success: true });
});

// Serve product images statically (authenticated)
router.get('/images/:filename', clientAuth, (req, res) => {
  const fp = path.join(PRODUCT_IMAGES_DIR, path.basename(req.params.filename));
  if (!fs.existsSync(fp)) return res.status(404).json({ error: 'No encontrado' });
  res.sendFile(fp);
});

module.exports = router;
