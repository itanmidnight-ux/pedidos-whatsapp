const express = require('express');
const router = express.Router();
const { jwtAuth, adminAuth } = require('../middleware/auth');
const { getDB } = require('../db/database');

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

router.get('/', jwtAuth, (req, res) => {
  const products = getDB().prepare('SELECT * FROM products ORDER BY favorite DESC, name ASC').all();
  res.json(products.map(p => ({ ...p, aliases: JSON.parse(p.aliases || '[]') })));
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
  getDB().prepare('DELETE FROM products WHERE id = ?').run(id);
  res.json({ success: true });
});

module.exports = router;
