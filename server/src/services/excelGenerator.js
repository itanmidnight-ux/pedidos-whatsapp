'use strict';
const ExcelJS = require('exceljs');
const fs   = require('fs');
const path = require('path');
const { getDB } = require('../db/database');
const logger = require('../utils/logger');
const {
  CATEGORIES, getFinancialSummary, getSalesByDay, getSalesByProduct,
  getEmployeePerformance, getCustomerReport,
} = require('./pdfGenerator');

const BRAND = 'FF0D4F1C';

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

  if (cats.includes('resumen')) {
    const s = getFinancialSummary(db, fromISO, toISO);
    const ws = wb.addWorksheet('Resumen');
    ws.columns = [{ header: 'Métrica', key: 'k', width: 28 }, { header: 'Valor', key: 'v', width: 20 }];
    styleHeaderRow(ws.getRow(1));
    ws.addRow({ k: 'Pedidos totales', v: s.total });
    ws.addRow({ k: 'Entregados', v: s.entregados });
    ws.addRow({ k: 'Cancelados', v: s.cancelados });
    ws.addRow({ k: 'Fiados', v: s.fiados });
    ws.addRow({ k: 'Ingresos', v: Number(s.ingresos) });
    ws.addRow({ k: 'Ticket promedio', v: Math.round(Number(s.ticket_promedio)) });
    ws.getColumn('v').numFmt = '#,##0';
  }

  if (cats.includes('ventas_dia')) {
    const rows = getSalesByDay(db, fromISO, toISO);
    const ws = wb.addWorksheet('Ventas por día', { views: [{ state: 'frozen', ySplit: 1 }] });
    ws.columns = [
      { header: 'Fecha', key: 'dia', width: 16 },
      { header: 'Pedidos', key: 'pedidos', width: 12 },
      { header: 'Ingresos', key: 'ingresos', width: 16 },
    ];
    styleHeaderRow(ws.getRow(1));
    for (const r of rows) ws.addRow({ dia: r.dia, pedidos: r.pedidos, ingresos: Number(r.ingresos) });
    ws.getColumn('ingresos').numFmt = '$#,##0';
  }

  if (cats.includes('ventas_producto')) {
    const rows = getSalesByProduct(db, fromISO, toISO);
    const ws = wb.addWorksheet('Ventas por producto', { views: [{ state: 'frozen', ySplit: 1 }] });
    ws.columns = [
      { header: 'Producto', key: 'producto', width: 30 },
      { header: 'Unidades', key: 'unidades', width: 12 },
      { header: 'Ingresos', key: 'ingresos', width: 16 },
    ];
    styleHeaderRow(ws.getRow(1));
    for (const r of rows) ws.addRow({ producto: sanitizeCell(r.producto), unidades: r.unidades, ingresos: Number(r.ingresos) });
    ws.getColumn('ingresos').numFmt = '$#,##0';
  }

  if (cats.includes('empleados')) {
    const rows = getEmployeePerformance(db, fromISO, toISO);
    const ws = wb.addWorksheet('Empleados', { views: [{ state: 'frozen', ySplit: 1 }] });
    ws.columns = [
      { header: 'Usuario', key: 'username', width: 16 },
      { header: 'Nombre', key: 'nombre', width: 22 },
      { header: 'Entregados', key: 'entregados', width: 14 },
      { header: 'Min. promedio', key: 'minutos_prom', width: 16 },
    ];
    styleHeaderRow(ws.getRow(1));
    for (const r of rows) ws.addRow({ username: r.username, nombre: sanitizeCell(r.nombre), entregados: r.entregados, minutos_prom: r.minutos_prom || 0 });
  }

  if (cats.includes('clientes')) {
    const { nuevos, recurrentes, clientes } = getCustomerReport(db, fromISO, toISO);
    const ws = wb.addWorksheet('Clientes', { views: [{ state: 'frozen', ySplit: 1 }] });
    ws.columns = [
      { header: 'Cliente', key: 'cliente', width: 24 },
      { header: 'Teléfono', key: 'telefono', width: 16 },
      { header: 'Pedidos', key: 'pedidos', width: 12 },
      { header: 'Gastado', key: 'gastado', width: 16 },
    ];
    styleHeaderRow(ws.getRow(1));
    ws.getRow(1).getCell(6).value = `Nuevos: ${nuevos}  Recurrentes: ${recurrentes}`;
    for (const c of clientes) {
      ws.addRow({ cliente: sanitizeCell(c.name || c.phone || 'N/A'), telefono: c.phone || '', pedidos: c.pedidos, gastado: Number(c.gastado) });
    }
    ws.getColumn('gastado').numFmt = '$#,##0';
  }

  const reportsDir = process.env.REPORTS_DIR || path.join(__dirname, '../../reports');
  if (!fs.existsSync(reportsDir)) fs.mkdirSync(reportsDir, { recursive: true });
  const filename = `datos-${fromISO}_a_${toISO}.xlsx`;
  const filepath = path.join(reportsDir, filename);
  await wb.xlsx.writeFile(filepath);

  logger.info({ filepath, categories: cats }, '[Excel] reporte por categorias generado');
  return filepath;
}

module.exports = { generateRangeReportXLSX };
