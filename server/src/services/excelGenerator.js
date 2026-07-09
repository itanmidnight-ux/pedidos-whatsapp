'use strict';
const ExcelJS = require('exceljs');
const fs   = require('fs');
const path = require('path');
const { getDB } = require('../db/database');
const logger = require('../utils/logger');

const TZ = 'America/Bogota';
const BRAND = 'FF0D4F1C';

function fmtDate(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleString('es-CO', {
    timeZone: TZ, day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit',
  });
}

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

// ── Reporte de rango a Excel: pedidos + cuentas (clientes) ─────────────
// Dos hojas separadas -- pedidos es el detalle transaccional, cuentas es
// el resumen por cliente ("cuenta empresarial") que pidió el usuario.
async function generateRangeReportXLSX(fromISO, toISO) {
  const db = getDB();

  const orders = db.prepare(`
    SELECT o.id, o.requested_at, o.delivered_at, o.status, o.product_name, o.product_price,
           o.is_fiado, o.delivery_address, o.wa_message,
           c.phone, c.name AS customer_name, u.display_name AS delivered_by_name
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN users     u ON o.claimed_by  = u.id
    WHERE date(o.requested_at, 'localtime') BETWEEN ? AND ?
    ORDER BY o.requested_at ASC
  `).all(fromISO, toISO);

  const itemsStmt = db.prepare('SELECT * FROM order_items WHERE order_id=?');

  const accounts = db.prepare(`
    SELECT c.phone, c.name,
      COUNT(DISTINCT o.id) AS total_pedidos,
      COALESCE(SUM(CASE WHEN o.status IN ('entregado','delivered') THEN o.product_price ELSE 0 END), 0) AS total_gastado,
      MIN(o.requested_at) AS primer_pedido,
      MAX(o.requested_at) AS ultimo_pedido,
      (SELECT COUNT(*) FROM messages m WHERE m.phone = c.phone) AS total_mensajes
    FROM customers c
    LEFT JOIN orders o ON o.customer_id = c.id AND date(o.requested_at, 'localtime') BETWEEN ? AND ?
    GROUP BY c.id
    HAVING total_pedidos > 0 OR total_mensajes > 0
    ORDER BY total_gastado DESC
  `).all(fromISO, toISO);

  const wb = new ExcelJS.Workbook();
  wb.creator = 'Concentrados Monserrath';
  wb.created = new Date(fromISO);

  // ── Hoja: Pedidos ──────────────────────────────────────────────
  const wsOrders = wb.addWorksheet('Pedidos', { views: [{ state: 'frozen', ySplit: 1 }] });
  wsOrders.columns = [
    { header: '#Pedido',       key: 'id',        width: 10 },
    { header: 'Cliente',       key: 'cliente',    width: 24 },
    { header: 'Teléfono',      key: 'telefono',   width: 16 },
    { header: 'Producto',      key: 'producto',   width: 28 },
    { header: 'Precio',        key: 'precio',     width: 14 },
    { header: 'Estado',        key: 'estado',     width: 14 },
    { header: 'Fiado',         key: 'fiado',       width: 10 },
    { header: 'Dirección',     key: 'direccion',  width: 30 },
    { header: 'Solicitado',    key: 'solicitado', width: 20 },
    { header: 'Entregado',     key: 'entregado',  width: 20 },
    { header: 'Atendió',       key: 'atendio',    width: 18 },
  ];
  styleHeaderRow(wsOrders.getRow(1));
  wsOrders.autoFilter = { from: 'A1', to: 'K1' };

  for (const o of orders) {
    const items = itemsStmt.all(o.id);
    const productLabel = items.length > 1
      ? items.map(it => `${it.quantity}x ${it.product_name}`).join(', ')
      : o.product_name;
    wsOrders.addRow({
      id: o.id,
      cliente: sanitizeCell(o.customer_name || o.phone || 'N/A'),
      telefono: o.phone || '',
      producto: sanitizeCell(productLabel),
      precio: o.product_price ? Number(o.product_price) : null,
      estado: o.status,
      fiado: o.is_fiado ? 'Sí' : 'No',
      direccion: sanitizeCell(o.delivery_address || ''),
      solicitado: fmtDate(o.requested_at),
      entregado: fmtDate(o.delivered_at),
      atendio: sanitizeCell(o.delivered_by_name || ''),
    });
  }
  wsOrders.getColumn('precio').numFmt = '$#,##0';

  // ── Hoja: Cuentas (clientes) ───────────────────────────────────
  const wsAccounts = wb.addWorksheet('Cuentas', { views: [{ state: 'frozen', ySplit: 1 }] });
  wsAccounts.columns = [
    { header: 'Cliente',        key: 'cliente',    width: 24 },
    { header: 'Teléfono',       key: 'telefono',   width: 16 },
    { header: 'Pedidos',        key: 'pedidos',    width: 12 },
    { header: 'Total gastado',  key: 'gastado',    width: 16 },
    { header: 'Mensajes',       key: 'mensajes',   width: 12 },
    { header: 'Primer pedido',  key: 'primero',    width: 20 },
    { header: 'Último pedido',  key: 'ultimo',     width: 20 },
  ];
  styleHeaderRow(wsAccounts.getRow(1));
  wsAccounts.autoFilter = { from: 'A1', to: 'G1' };

  for (const a of accounts) {
    wsAccounts.addRow({
      cliente: sanitizeCell(a.name || a.phone || 'N/A'),
      telefono: a.phone || '',
      pedidos: a.total_pedidos,
      gastado: Number(a.total_gastado) || 0,
      mensajes: a.total_mensajes,
      primero: fmtDate(a.primer_pedido),
      ultimo: fmtDate(a.ultimo_pedido),
    });
  }
  wsAccounts.getColumn('gastado').numFmt = '$#,##0';

  const reportsDir = process.env.REPORTS_DIR || path.join(__dirname, '../../reports');
  if (!fs.existsSync(reportsDir)) fs.mkdirSync(reportsDir, { recursive: true });
  const filename = `datos-${fromISO}_a_${toISO}.xlsx`;
  const filepath = path.join(reportsDir, filename);
  await wb.xlsx.writeFile(filepath);

  logger.info({ filepath, orders: orders.length, cuentas: accounts.length }, '[Excel] reporte de rango generado');
  return filepath;
}

module.exports = { generateRangeReportXLSX };
