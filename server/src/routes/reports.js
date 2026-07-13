'use strict';
const express = require('express');
const router  = express.Router();
const path    = require('path');
const { adminAuth } = require('../middleware/auth');
const { generateRangeReportPDF, CATEGORIES } = require('../services/pdfGenerator');
const { generateRangeReportXLSX } = require('../services/excelGenerator');

function isValidDate(s) { return /^\d{4}-\d{2}-\d{2}$/.test(String(s || '')); }

function validCategories(categories) {
  return Array.isArray(categories) && categories.length > 0
    && categories.every(c => CATEGORIES.includes(c));
}

// POST /api/reports/export-range — Genera PDF con las categorias elegidas de un rango
router.post('/export-range', adminAuth, async (req, res) => {
  const { from, to, categories } = req.body;
  if (!isValidDate(from) || !isValidDate(to))
    return res.status(400).json({ error: 'from/to requeridos (YYYY-MM-DD)' });
  if (from > to)
    return res.status(400).json({ error: '"from" no puede ser posterior a "to"' });
  if (!validCategories(categories))
    return res.status(400).json({ error: `categories requerido (subconjunto no vacio de: ${CATEGORIES.join(', ')})` });

  try {
    const filepath = await generateRangeReportPDF(from, to, categories);
    res.json({ success: true, filename: path.basename(filepath), filepath });
  } catch (e) {
    res.status(500).json({ error: 'Error generando el reporte' });
  }
});

// POST /api/reports/export-range-excel — Genera Excel con las categorias elegidas de un rango
router.post('/export-range-excel', adminAuth, async (req, res) => {
  const { from, to, categories } = req.body;
  if (!isValidDate(from) || !isValidDate(to))
    return res.status(400).json({ error: 'from/to requeridos (YYYY-MM-DD)' });
  if (from > to)
    return res.status(400).json({ error: '"from" no puede ser posterior a "to"' });
  if (!validCategories(categories))
    return res.status(400).json({ error: `categories requerido (subconjunto no vacio de: ${CATEGORIES.join(', ')})` });

  try {
    const filepath = await generateRangeReportXLSX(from, to, categories);
    res.json({ success: true, filename: path.basename(filepath), filepath });
  } catch (e) {
    res.status(500).json({ error: 'Error generando el Excel' });
  }
});

// GET /api/reports/categories — lista de categorias validas (dialogo del dashboard)
router.get('/categories', adminAuth, (req, res) => {
  res.json({ categories: CATEGORIES });
});

module.exports = router;
