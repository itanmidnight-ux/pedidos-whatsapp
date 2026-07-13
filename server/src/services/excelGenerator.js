'use strict';
const ExcelJS = require('exceljs');
const fs   = require('fs');
const path = require('path');
const { getDB } = require('../db/database');
const logger = require('../utils/logger');
const {
  CATEGORIES, CATEGORY_LABELS, CATEGORY_SLUGS, getFinancialSummary, getSalesByDay, getSalesByProduct,
  getEmployeePerformance, getCustomerReport,
} = require('./pdfGenerator');

const BRAND = 'FF0D4F1C';
const BRAND_SOFT = 'FFE8F0E6';

// Formula injection (CSV/Excel): si una celda de texto controlado por el
// usuario empieza con =, +, - o @, Excel la interpreta como formula al
// abrirla -- puede ejecutar comandos. Se antepone un apostrofe (fuerza texto
// literal en Excel, no se ve en la celda) a cualquier valor de string que
// empiece con esos caracteres. Numeros/fechas no se tocan.
function sanitizeCell(value) {
  if (typeof value !== 'string') return value;
  return /^[=+\-@]/.test(value) ? `'${value}` : value;
}

function styleHeaderRow(row) {
  row.eachCell(cell => {
    cell.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: BRAND } };
    cell.alignment = { vertical: 'middle' };
  });
  row.height = 20;
}

// Fila de titulo (categoria + rango de fechas) arriba de cada hoja, para
// que quede claro que es el archivo aunque se abra suelto sin ver el
// nombre del archivo -- y una fila de zebra striping suave en los datos
// para que el ojo no pierda la fila al leer de izquierda a derecha.
function addTitleRow(ws, title, subtitle, numCols) {
  ws.mergeCells(1, 1, 1, numCols);
  const cell = ws.getCell(1, 1);
  cell.value = `${title}  —  ${subtitle}`;
  cell.font = { bold: true, size: 13, color: { argb: BRAND } };
  cell.alignment = { vertical: 'middle' };
  ws.getRow(1).height = 26;
  ws.addRow([]);
}

function zebraStripe(ws, startRow) {
  for (let i = startRow; i <= ws.rowCount; i++) {
    if ((i - startRow) % 2 === 1) {
      ws.getRow(i).eachCell({ includeEmpty: true }, cell => {
        cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: BRAND_SOFT } };
      });
    }
  }
}

// ── Reporte por categorias a Excel ──────────────────────────────────────
// Una hoja por categoria elegida -- nunca incluye contenido de chats, y
// reusa las mismas queries de pdfGenerator.js (una sola fuente de verdad
// para los calculos de ventas/empleados/clientes entre PDF y Excel).
async function generateRangeReportXLSX(fromISO, toISO, categories) {
  const cats = (categories && categories.length ? categories : CATEGORIES).filter(c => CATEGORIES.includes(c));
  const db = getDB();
  const wb = new ExcelJS.Workbook();
  wb.creator = 'Concentrados Monserrath';
  wb.created = new Date(fromISO);
  const rangeLabel = `${fromISO} a ${toISO}`;

  if (cats.includes('resumen')) {
    const s = getFinancialSummary(db, fromISO, toISO);
    const ws = wb.addWorksheet('Resumen');
    ws.columns = [{ key: 'k', width: 28 }, { key: 'v', width: 20 }];
    addTitleRow(ws, CATEGORY_LABELS.resumen, rangeLabel, 2);
    ws.getRow(3).values = ['Métrica', 'Valor'];
    styleHeaderRow(ws.getRow(3));
    ws.addRow({ k: 'Pedidos totales', v: s.total });
    ws.addRow({ k: 'Entregados', v: s.entregados });
    ws.addRow({ k: 'Cancelados', v: s.cancelados });
    ws.addRow({ k: 'Fiados', v: s.fiados });
    ws.addRow({ k: 'Ingresos', v: Number(s.ingresos) });
    ws.addRow({ k: 'Ticket promedio', v: Math.round(Number(s.ticket_promedio)) });
    ws.getColumn('v').numFmt = '#,##0';
    zebraStripe(ws, 4);
  }

  if (cats.includes('ventas_dia')) {
    const rows = getSalesByDay(db, fromISO, toISO);
    const ws = wb.addWorksheet('Ventas por día', { views: [{ state: 'frozen', ySplit: 3 }] });
    ws.columns = [{ key: 'dia', width: 16 }, { key: 'pedidos', width: 12 }, { key: 'ingresos', width: 16 }];
    addTitleRow(ws, CATEGORY_LABELS.ventas_dia, rangeLabel, 3);
    ws.getRow(3).values = ['Fecha', 'Pedidos', 'Ingresos'];
    styleHeaderRow(ws.getRow(3));
    if (!rows.length) ws.addRow({ dia: 'Sin ventas registradas en este rango.' });
    for (const r of rows) ws.addRow({ dia: r.dia, pedidos: r.pedidos, ingresos: Number(r.ingresos) });
    ws.getColumn('ingresos').numFmt = '$#,##0';
    zebraStripe(ws, 4);
  }

  if (cats.includes('ventas_producto')) {
    const rows = getSalesByProduct(db, fromISO, toISO);
    const ws = wb.addWorksheet('Ventas por producto', { views: [{ state: 'frozen', ySplit: 3 }] });
    ws.columns = [{ key: 'producto', width: 30 }, { key: 'unidades', width: 12 }, { key: 'ingresos', width: 16 }];
    addTitleRow(ws, CATEGORY_LABELS.ventas_producto, rangeLabel, 3);
    ws.getRow(3).values = ['Producto', 'Unidades', 'Ingresos'];
    styleHeaderRow(ws.getRow(3));
    if (!rows.length) ws.addRow({ producto: 'Sin ventas registradas en este rango.' });
    for (const r of rows) ws.addRow({ producto: sanitizeCell(r.producto), unidades: r.unidades, ingresos: Number(r.ingresos) });
    ws.getColumn('ingresos').numFmt = '$#,##0';
    zebraStripe(ws, 4);
  }

  if (cats.includes('empleados')) {
    const rows = getEmployeePerformance(db, fromISO, toISO);
    const ws = wb.addWorksheet('Empleados', { views: [{ state: 'frozen', ySplit: 3 }] });
    ws.columns = [
      { key: 'username', width: 16 }, { key: 'nombre', width: 22 },
      { key: 'entregados', width: 14 }, { key: 'minutos_prom', width: 16 },
    ];
    addTitleRow(ws, CATEGORY_LABELS.empleados, rangeLabel, 4);
    ws.getRow(3).values = ['Usuario', 'Nombre', 'Entregados', 'Min. promedio'];
    styleHeaderRow(ws.getRow(3));
    if (!rows.length) ws.addRow({ username: 'Sin entregas registradas en este rango.' });
    for (const r of rows) ws.addRow({ username: r.username, nombre: sanitizeCell(r.nombre), entregados: r.entregados, minutos_prom: r.minutos_prom || 0 });
    zebraStripe(ws, 4);
  }

  if (cats.includes('clientes')) {
    const { nuevos, recurrentes, clientes } = getCustomerReport(db, fromISO, toISO);
    const ws = wb.addWorksheet('Clientes', { views: [{ state: 'frozen', ySplit: 3 }] });
    ws.columns = [
      { key: 'cliente', width: 24 }, { key: 'telefono', width: 16 },
      { key: 'pedidos', width: 12 }, { key: 'gastado', width: 16 },
    ];
    addTitleRow(ws, CATEGORY_LABELS.clientes, `${rangeLabel}  ·  Nuevos: ${nuevos}  ·  Recurrentes: ${recurrentes}`, 4);
    ws.getRow(3).values = ['Cliente', 'Teléfono', 'Pedidos', 'Gastado'];
    styleHeaderRow(ws.getRow(3));
    if (!clientes.length) ws.addRow({ cliente: 'Sin clientes con pedidos en este rango.' });
    for (const c of clientes) {
      ws.addRow({ cliente: sanitizeCell(c.name || c.phone || 'N/A'), telefono: c.phone || '', pedidos: c.pedidos, gastado: Number(c.gastado) });
    }
    ws.getColumn('gastado').numFmt = '$#,##0';
    zebraStripe(ws, 4);
  }

  const reportsDir = process.env.REPORTS_DIR || path.join(__dirname, '../../reports');
  if (!fs.existsSync(reportsDir)) fs.mkdirSync(reportsDir, { recursive: true });
  // Mismo criterio que el PDF: nombre de archivo identifica la categoria
  // exacta, nunca se pisan entre si cuando el dashboard pide varias.
  const slug = cats.map(c => CATEGORY_SLUGS[c]).join('_');
  const filename = `${slug}-${fromISO}_a_${toISO}.xlsx`;
  const filepath = path.join(reportsDir, filename);
  await wb.xlsx.writeFile(filepath);

  logger.info({ filepath, categories: cats }, '[Excel] reporte por categorias generado');
  return filepath;
}

module.exports = { generateRangeReportXLSX };
