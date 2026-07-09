'use strict';
const PDFDocument = require('pdfkit');
const fs   = require('fs');
const path = require('path');
const { getDB } = require('../db/database');
const logger = require('../utils/logger');

const TZ = 'America/Bogota';

// PDFKit con las fuentes estandar (Helvetica) no tiene glyphs para emoji --
// en vez de renderizar el caracter real, dibuja basura tipo "Ø=ÜK" y ademas
// descuadra el ancho calculado del texto (por eso el resto de la linea
// terminaba superpuesto). Se quitan por completo en vez de intentar
// soportarlos: es lo unico realmente confiable con las fuentes base de PDFKit.
function stripEmoji(str) {
  if (str == null) return '';
  return String(str)
    .replace(/[\u{1F000}-\u{1FFFF}]/gu, '')  // emoji principales (incl. modificadores de tono)
    .replace(/[\u{2190}-\u{21FF}]/gu, '')     // flechas
    .replace(/[\u{2300}-\u{23FF}]/gu, '')     // simbolos tecnicos varios
    .replace(/[\u{2600}-\u{27BF}]/gu, '')     // simbolos varios + dingbats (✅ ❌ etc)
    .replace(/[\u{2B00}-\u{2BFF}]/gu, '')     // simbolos/flechas varios
    .replace(/[\u{FE00}-\u{FE0F}]/gu, '')     // selectores de variacion
    .replace(/\u200D/g, '')                   // zero-width joiner (emoji compuestos)
    .replace(/[ \t]{2,}/g, ' ')
    .trim();
}

function fmt(iso) {
  if (!iso) return 'N/A';
  return new Date(iso).toLocaleString('es-CO', {
    timeZone: TZ, day: '2-digit', month: '2-digit',
    year: 'numeric', hour: '2-digit', minute: '2-digit',
  });
}

function fmtTime(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleTimeString('es-CO', {
    timeZone: TZ, hour: '2-digit', minute: '2-digit',
  });
}

function fmtPhone(phone) {
  if (phone && phone.length === 12 && phone.startsWith('57')) {
    return `+57 ${phone.substring(2, 5)} ${phone.substring(5, 8)} ${phone.substring(8)}`;
  }
  return phone ? `+${phone}` : 'N/A';
}

// Salta de pagina si no alcanza el espacio pedido -- evita que un bloque
// (encabezado, pedido, linea de chat) quede cortado justo al borde.
function ensureSpace(doc, needed) {
  const bottom = doc.page.height - doc.page.margins.bottom;
  if (doc.y + needed > bottom) doc.addPage();
}

// El bug de superposicion: `doc.rect().fill()` NO mueve el cursor de texto,
// y el .text() con y absoluto (doc.y - N) tampoco lo deja en un lugar
// predecible despues. Se fuerza el cursor a una posicion fija (debajo de la
// barra) al final, sin importar como midio PDFKit el texto -- asi nunca
// vuelve a quedar contenido dibujado encima del propio encabezado.
function sectionHeader(doc, title) {
  ensureSpace(doc, 50);
  doc.moveDown(0.5);
  const startY = doc.y;
  const barHeight = 24;
  const width = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  doc.rect(doc.page.margins.left, startY, width, barHeight).fill('#1B5E20');
  doc.fillColor('white').fontSize(12).font('Helvetica-Bold')
     .text(stripEmoji(title), doc.page.margins.left + 10, startY + 6, { width: width - 20, lineBreak: false });
  doc.font('Helvetica').fillColor('#333');
  doc.y = startY + barHeight + 10;
}

function divider(doc) {
  doc.moveTo(doc.page.margins.left, doc.y)
     .lineTo(doc.page.width - doc.page.margins.right, doc.y)
     .strokeColor('#dddddd').lineWidth(0.5).stroke();
  doc.moveDown(0.5);
}

function drawCover(doc, subtitle, rangeLabel) {
  doc.rect(0, 0, doc.page.width, 110).fill('#0D4F1C');
  doc.fillColor('white').fontSize(20).font('Helvetica-Bold')
     .text('CONCENTRADOS MONSERRATH', 40, 28, { align: 'center' });
  doc.fontSize(13).font('Helvetica').text(subtitle, { align: 'center' });
  doc.fontSize(10).fillColor('#a5d6a7').text(rangeLabel, { align: 'center' });
  doc.y = 140;
  doc.fillColor('#333');
}

function drawSummary(doc, rows) {
  doc.fontSize(13).font('Helvetica-Bold').fillColor('#1B5E20').text('Resumen');
  doc.moveDown(0.4);
  for (const [label, val] of rows) {
    doc.fontSize(11).font('Helvetica').fillColor('#555')
       .text(`${stripEmoji(label)}: `, { continued: true })
       .font('Helvetica-Bold').fillColor('#111').text(String(val));
  }
}

// ── Apartado por cliente: su info + sus pedidos + su chat, todo junto ──
// (antes eran dos secciones globales separadas -- "todos los pedidos" y
// luego "todos los chats" -- que obligaba a buscar por dos lados la
// info de un mismo cliente. Ahora es un registro por cuenta/cliente.)
function renderCustomerSection(doc, phone, entry) {
  ensureSpace(doc, 60);
  doc.fontSize(13).font('Helvetica-Bold').fillColor('#1B5E20')
     .text(stripEmoji(entry.displayName) || phone);
  doc.fontSize(9).font('Helvetica').fillColor('#888').text(fmtPhone(phone));
  doc.moveDown(0.4);

  if (entry.orders.length) {
    doc.fontSize(10).font('Helvetica-Bold').fillColor('#444').text(`PEDIDOS (${entry.orders.length})`);
    doc.moveDown(0.2);
    entry.orders.forEach((order, idx) => {
      ensureSpace(doc, 90);
      const productLabel = order.items?.length > 1
        ? order.items.map(it => `${it.quantity}x ${stripEmoji(it.product_name)}`).join(', ')
        : stripEmoji(order.product_name);
      doc.fontSize(10).font('Helvetica-Bold').fillColor('#1B5E20')
         .text(`#${idx + 1}  ${productLabel}  [${order.status}]`);
      doc.font('Helvetica').fontSize(9).fillColor('#333');
      [
        ['Entregó',    order.delivered_by_name || 'N/A'],
        ['Dirección',  stripEmoji(order.delivery_address) || 'N/A'],
        ['Precio',     order.product_price ? `$${Number(order.product_price).toLocaleString('es-CO')}` : 'N/A'],
        ['Fiado',      order.is_fiado ? 'Sí' : 'No'],
        ['Solicitado', fmt(order.requested_at)],
        ['Entregado',  fmt(order.delivered_at)],
        ['Mensaje WA', stripEmoji(order.wa_message) || '—'],
      ].forEach(([lbl, val]) => {
        doc.fillColor('#888').text(`  ${lbl}: `, { continued: true })
           .fillColor('#222').text(String(val).slice(0, 120));
      });
      doc.moveDown(0.3);
    });
    doc.moveDown(0.2);
  }

  if (entry.msgs.length) {
    doc.fontSize(10).font('Helvetica-Bold').fillColor('#444').text(`CHAT (${entry.msgs.length} mensajes)`);
    doc.moveDown(0.2);
    for (const msg of entry.msgs) {
      ensureSpace(doc, 30);
      const isOut   = msg.direction === 'outbound';
      const tag     = isOut ? '[Bot/Admin]' : '[Cliente]';
      const color   = isOut ? '#1565C0' : '#333';
      const time    = fmtTime(msg.created_at);
      const delTag  = msg.deleted_at ? ' (borrado)' : '';
      const body    = msg.media_type === 'audio' ? 'Mensaje de voz'
                    : msg.media_type === 'image' ? 'Imagen'
                    : msg.media_type === 'video' ? 'Video'
                    : msg.media_type === 'document' ? 'Documento'
                    : stripEmoji(msg.content).slice(0, 300);
      doc.fontSize(9).font('Helvetica-Bold').fillColor(color)
         .text(`  ${time}  ${tag}${delTag}  `, { continued: true })
         .font('Helvetica').fillColor('#222').text(body || '—');
    }
  }

  doc.moveDown(0.3);
  divider(doc);
}

function paginate(doc, filename) {
  const pages = doc.bufferedPageRange();
  for (let i = 0; i < pages.count; i++) {
    doc.switchToPage(i);
    doc.fontSize(8).fillColor('#aaa')
       .text(`Página ${i + 1} de ${pages.count}  •  ${filename}`,
         doc.page.margins.left, doc.page.height - 30,
         { align: 'center', lineBreak: false });
  }
}

function buildCustomerMap(orders, messages) {
  const byPhone = new Map();
  const ensure = (phone, displayName) => {
    if (!byPhone.has(phone)) byPhone.set(phone, { displayName: displayName || phone, orders: [], msgs: [] });
    const entry = byPhone.get(phone);
    if (displayName && entry.displayName === phone) entry.displayName = displayName;
    return entry;
  };
  for (const o of orders) ensure(o.phone || `pedido-${o.id}`, o.customer_name).orders.push(o);
  for (const m of messages) ensure(m.phone, m.display_name).msgs.push(m);
  const phones = [...byPhone.keys()].sort((a, b) =>
    byPhone.get(a).displayName.localeCompare(byPhone.get(b).displayName, 'es'));
  return { byPhone, phones };
}

async function generateDailyPDF() {
  const db = getDB();
  const now = new Date();
  const todayISO = now.toISOString().split('T')[0];
  const todayLabel = now.toLocaleDateString('es-CO', {
    timeZone: TZ, weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
  });

  const orders = db.prepare(`
    SELECT o.*, c.phone, c.name AS customer_name,
           u.display_name AS delivered_by_name
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN users     u ON o.claimed_by  = u.id
    WHERE date(o.delivered_at, 'localtime') = ?
      AND o.status IN ('delivered','entregado')
    ORDER BY o.delivered_at ASC
  `).all(todayISO);

  const itemsStmt = db.prepare('SELECT * FROM order_items WHERE order_id=?');
  orders.forEach(o => { o.items = itemsStmt.all(o.id); });

  const messages = db.prepare(`
    SELECT m.*, COALESCE(c.name, m.customer_name) AS display_name
    FROM messages m
    LEFT JOIN customers c ON c.phone = m.phone
    WHERE date(m.created_at, 'localtime') = ? AND m.deleted_at IS NULL
    ORDER BY m.phone, m.created_at ASC
  `).all(todayISO);

  const { byPhone, phones } = buildCustomerMap(orders, messages);

  const reportsDir = process.env.REPORTS_DIR || path.join(__dirname, '../../reports');
  if (!fs.existsSync(reportsDir)) fs.mkdirSync(reportsDir, { recursive: true });

  const filename = `registro-${todayISO}.pdf`;
  const filepath = path.join(reportsDir, filename);
  const doc = new PDFDocument({ margin: 40, size: 'A4', bufferPages: true });
  const stream = fs.createWriteStream(filepath);
  doc.pipe(stream);

  drawCover(doc, 'Registro Diario — Pedidos y Chats', todayLabel.charAt(0).toUpperCase() + todayLabel.slice(1));

  const totalIngresos = orders.reduce((s, o) => s + (Number(o.product_price) || 0), 0);
  const totalFiado    = orders.filter(o => o.is_fiado).length;
  drawSummary(doc, [
    ['Pedidos entregados', orders.length],
    ['Ingresos del día',   `$${totalIngresos.toLocaleString('es-CO')}`],
    ['Pedidos fiados',     totalFiado],
    ['Cuentas con actividad', phones.length],
    ['Mensajes totales',   messages.length],
  ]);

  doc.addPage();
  sectionHeader(doc, `REGISTRO POR CLIENTE (${phones.length})`);
  if (!phones.length) {
    doc.fontSize(12).fillColor('#777').text('Sin actividad hoy.', { align: 'center' });
  } else {
    for (const phone of phones) renderCustomerSection(doc, phone, byPhone.get(phone));
  }

  paginate(doc, filename);
  doc.end();
  await new Promise((resolve, reject) => {
    stream.on('finish', resolve);
    stream.on('error', reject);
  });

  if (orders.length) {
    const placeholders = orders.map(() => '?').join(',');
    db.prepare(`UPDATE orders SET pdf_exported=1 WHERE id IN (${placeholders})`)
      .run(...orders.map(o => o.id));
  }

  logger.info({ filepath, orders: orders.length, cuentas: phones.length }, '[PDF] generado');
  return filepath;
}

// ── Reporte por rango de fechas (pestaña "Datos" del dashboard) ────────
// A diferencia de generateDailyPDF: incluye pedidos de CUALQUIER estado
// (no solo entregados) y TODOS los mensajes del rango, incluidos los ya
// borrados por el staff (deleted_at) -- el requisito es que el texto de
// los chats quede disponible para exportar aunque ya no se vea en la app.
async function generateRangeReportPDF(fromISO, toISO) {
  const db = getDB();
  const fromLabel = new Date(fromISO).toLocaleDateString('es-CO', { timeZone: TZ, day: '2-digit', month: 'long', year: 'numeric' });
  const toLabel   = new Date(toISO).toLocaleDateString('es-CO',   { timeZone: TZ, day: '2-digit', month: 'long', year: 'numeric' });

  const orders = db.prepare(`
    SELECT o.*, c.phone, c.name AS customer_name,
           u.display_name AS delivered_by_name
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN users     u ON o.claimed_by  = u.id
    WHERE date(o.requested_at, 'localtime') BETWEEN ? AND ?
    ORDER BY o.requested_at ASC
  `).all(fromISO, toISO);

  const itemsStmt = db.prepare('SELECT * FROM order_items WHERE order_id=?');
  orders.forEach(o => { o.items = itemsStmt.all(o.id); });

  const messages = db.prepare(`
    SELECT m.*, COALESCE(c.name, m.customer_name) AS display_name
    FROM messages m
    LEFT JOIN customers c ON c.phone = m.phone
    WHERE date(m.created_at, 'localtime') BETWEEN ? AND ?
    ORDER BY m.phone, m.created_at ASC
  `).all(fromISO, toISO);

  const { byPhone, phones } = buildCustomerMap(orders, messages);

  const reportsDir = process.env.REPORTS_DIR || path.join(__dirname, '../../reports');
  if (!fs.existsSync(reportsDir)) fs.mkdirSync(reportsDir, { recursive: true });

  const filename = `reporte-${fromISO}_a_${toISO}.pdf`;
  const filepath = path.join(reportsDir, filename);
  const doc = new PDFDocument({ margin: 40, size: 'A4', bufferPages: true });
  const stream = fs.createWriteStream(filepath);
  doc.pipe(stream);

  drawCover(doc, 'Reporte de Datos — Pedidos y Chats', `${fromLabel}  —  ${toLabel}`);

  const delivered      = orders.filter(o => ['entregado', 'delivered'].includes(o.status));
  const cancelled       = orders.filter(o => o.status === 'cancelled');
  const totalIngresos   = delivered.reduce((s, o) => s + (Number(o.product_price) || 0), 0);
  drawSummary(doc, [
    ['Pedidos totales',      orders.length],
    ['Entregados',           delivered.length],
    ['Cancelados',           cancelled.length],
    ['Ingresos del rango',   `$${totalIngresos.toLocaleString('es-CO')}`],
    ['Cuentas con actividad', phones.length],
    ['Mensajes totales',     messages.length],
  ]);

  doc.addPage();
  sectionHeader(doc, `REGISTRO POR CLIENTE (${phones.length}) -- incluye chats borrados`);
  if (!phones.length) {
    doc.fontSize(12).fillColor('#777').text('Sin actividad en este rango.', { align: 'center' });
  } else {
    for (const phone of phones) renderCustomerSection(doc, phone, byPhone.get(phone));
  }

  paginate(doc, filename);
  doc.end();
  await new Promise((resolve, reject) => {
    stream.on('finish', resolve);
    stream.on('error', reject);
  });

  logger.info({ filepath, orders: orders.length, cuentas: phones.length }, '[PDF] reporte de rango generado');
  return filepath;
}

module.exports = { generateDailyPDF, generateRangeReportPDF };
