'use strict';
const express = require('express');
const router  = express.Router();
const path    = require('path');
const { adminAuth } = require('../middleware/auth');
const { generateRangeReportPDF } = require('../services/pdfGenerator');
const { generateRangeReportXLSX } = require('../services/excelGenerator');

function isValidDate(s) { return /^\d{4}-\d{2}-\d{2}$/.test(String(s || '')); }

// POST /api/reports/export-range — Genera PDF con pedidos + chats de un rango
router.post('/export-range', adminAuth, async (req, res) => {
  const { from, to } = req.body;
  if (!isValidDate(from) || !isValidDate(to))
    return res.status(400).json({ error: 'from/to requeridos (YYYY-MM-DD)' });
  if (from > to)
    return res.status(400).json({ error: '"from" no puede ser posterior a "to"' });

  try {
    const filepath = await generateRangeReportPDF(from, to);
    res.json({ success: true, filename: path.basename(filepath), filepath });
  } catch (e) {
    res.status(500).json({ error: 'Error generando el reporte' });
  }
});

// POST /api/reports/export-range-excel — Genera Excel (pedidos + cuentas) de un rango
router.post('/export-range-excel', adminAuth, async (req, res) => {
  const { from, to } = req.body;
  if (!isValidDate(from) || !isValidDate(to))
    return res.status(400).json({ error: 'from/to requeridos (YYYY-MM-DD)' });
  if (from > to)
    return res.status(400).json({ error: '"from" no puede ser posterior a "to"' });

  try {
    const filepath = await generateRangeReportXLSX(from, to);
    res.json({ success: true, filename: path.basename(filepath), filepath });
  } catch (e) {
    res.status(500).json({ error: 'Error generando el Excel' });
  }
});

module.exports = router;
