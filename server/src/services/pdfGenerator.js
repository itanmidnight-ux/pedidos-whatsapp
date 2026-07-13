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

// ── Reporte por categorias (pestaña "Datos" del dashboard) ─────────────
// Cada categoria es un dato real de negocio (ventas, empleados, clientes),
// nunca contenido de chats -- eso es exclusivo de generateDailyPDF, que
// sigue igual y no se toca aca.
const CATEGORIES = ['resumen', 'ventas_dia', 'ventas_producto', 'empleados', 'clientes'];
const CATEGORY_LABELS = {
  resumen: 'Resumen financiero',
  ventas_dia: 'Ventas por día',
  ventas_producto: 'Ventas por producto',
  empleados: 'Desempeño de empleados',
  clientes: 'Clientes',
};
// Nombres de archivo ASCII (sin tildes/espacios) -- un archivo por
// categoria, nunca se pisan entre si aunque se pidan en la misma corrida.
const CATEGORY_SLUGS = {
  resumen: 'resumen-financiero',
  ventas_dia: 'ventas-por-dia',
  ventas_producto: 'ventas-por-producto',
  empleados: 'desempeno-empleados',
  clientes: 'clientes',
};

function getFinancialSummary(db, fromISO, toISO) {
  const row = db.prepare(`
    SELECT COUNT(*) AS total,
           COUNT(*) FILTER (WHERE status IN ('entregado','delivered')) AS entregados,
           COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelados,
           COUNT(*) FILTER (WHERE is_fiado = 1) AS fiados
    FROM orders WHERE date(requested_at,'localtime') BETWEEN ? AND ?
  `).get(fromISO, toISO);
  const ingresos = db.prepare(`
    SELECT COALESCE(SUM(oi.product_price*oi.quantity),0) AS t
    FROM orders o JOIN order_items oi ON oi.order_id=o.id
    WHERE o.status IN ('entregado','delivered') AND date(o.requested_at,'localtime') BETWEEN ? AND ?
  `).get(fromISO, toISO).t;
  const avg = db.prepare(`
    SELECT COALESCE(AVG(t),0) AS a FROM (
      SELECT SUM(oi.product_price*oi.quantity) t FROM orders o
      JOIN order_items oi ON oi.order_id=o.id
      WHERE o.status IN ('entregado','delivered') AND date(o.requested_at,'localtime') BETWEEN ? AND ?
      GROUP BY o.id)
  `).get(fromISO, toISO).a;
  return { ...row, ingresos, ticket_promedio: avg };
}

function getSalesByDay(db, fromISO, toISO) {
  return db.prepare(`
    SELECT date(o.delivered_at,'localtime') AS dia,
           COUNT(*) AS pedidos,
           SUM(oi.product_price*oi.quantity) AS ingresos
    FROM orders o JOIN order_items oi ON oi.order_id=o.id
    WHERE o.status IN ('entregado','delivered') AND date(o.delivered_at,'localtime') BETWEEN ? AND ?
    GROUP BY dia ORDER BY dia ASC
  `).all(fromISO, toISO);
}

function getSalesByProduct(db, fromISO, toISO) {
  return db.prepare(`
    SELECT oi.product_name AS producto,
           SUM(oi.quantity) AS unidades,
           SUM(oi.product_price*oi.quantity) AS ingresos
    FROM orders o JOIN order_items oi ON oi.order_id=o.id
    WHERE o.status IN ('entregado','delivered') AND date(o.requested_at,'localtime') BETWEEN ? AND ?
    GROUP BY oi.product_name ORDER BY ingresos DESC
  `).all(fromISO, toISO);
}

function getEmployeePerformance(db, fromISO, toISO) {
  return db.prepare(`
    SELECT u.username, COALESCE(u.display_name, u.username) AS nombre,
           COUNT(*) AS entregados,
           ROUND(AVG((julianday(o.delivered_at) - julianday(o.requested_at)) * 24 * 60)) AS minutos_prom
    FROM orders o JOIN users u ON u.id = o.claimed_by
    WHERE o.status IN ('entregado','delivered') AND date(o.requested_at,'localtime') BETWEEN ? AND ?
    GROUP BY u.id ORDER BY entregados DESC
  `).all(fromISO, toISO);
}

function getCustomerReport(db, fromISO, toISO) {
  const nuevos = db.prepare(`
    SELECT COUNT(*) AS c FROM customers WHERE date(created_at,'localtime') BETWEEN ? AND ?
  `).get(fromISO, toISO).c;
  const clientes = db.prepare(`
    SELECT c.name, c.phone, COUNT(*) AS pedidos,
           COALESCE(SUM(CASE WHEN o.status IN ('entregado','delivered') THEN o.product_price ELSE 0 END),0) AS gastado
    FROM orders o JOIN customers c ON c.id = o.customer_id
    WHERE date(o.requested_at,'localtime') BETWEEN ? AND ?
    GROUP BY o.customer_id ORDER BY gastado DESC
  `).all(fromISO, toISO);
  const recurrentes = clientes.filter(c => c.pedidos > 1).length;
  return { nuevos, recurrentes, clientes };
}

// Fila de columnas en texto plano (PDFKit no trae tablas): un renglon de
// headers en negrita/gris antes de los datos, con las mismas posiciones X
// fijas que las filas de datos -- para que el lector identifique cada
// columna sin ambiguedad, sin necesitar una tabla real.
function tableHeader(doc, cols) {
  ensureSpace(doc, 22);
  const y = doc.y;
  doc.fontSize(9).font('Helvetica-Bold').fillColor('#666');
  for (const [label, x] of cols) doc.text(label, x, y, { lineBreak: false });
  doc.moveDown(0.9);
  doc.moveTo(doc.page.margins.left, doc.y).lineTo(doc.page.width - doc.page.margins.right, doc.y)
     .strokeColor('#ddd').lineWidth(0.5).stroke();
  doc.moveDown(0.4);
}

function emptyState(doc, msg) {
  ensureSpace(doc, 30);
  doc.fontSize(11).font('Helvetica-Oblique').fillColor('#999').text(msg, { align: 'center' });
  doc.moveDown(0.5);
}

function renderCategorySection(doc, category, data) {
  sectionHeader(doc, CATEGORY_LABELS[category]);
  const left = doc.page.margins.left;

  if (category === 'resumen') {
    drawSummary(doc, [
      ['Pedidos totales', data.total],
      ['Entregados', data.entregados],
      ['Cancelados', data.cancelados],
      ['Fiados', data.fiados],
      ['Ingresos', `$${Number(data.ingresos).toLocaleString('es-CO')}`],
      ['Ticket promedio', `$${Math.round(Number(data.ticket_promedio)).toLocaleString('es-CO')}`],
    ]);
  } else if (category === 'ventas_dia') {
    if (!data.length) { emptyState(doc, 'Sin ventas registradas en este rango de fechas.'); return; }
    tableHeader(doc, [['Fecha', left], ['Pedidos', left + 160], ['Ingresos', left + 260]]);
    for (const row of data) {
      ensureSpace(doc, 20);
      const y = doc.y;
      doc.fontSize(10).font('Helvetica').fillColor('#333')
        .text(row.dia, left, y, { lineBreak: false })
        .text(String(row.pedidos), left + 160, y, { lineBreak: false })
        .text(`$${Number(row.ingresos).toLocaleString('es-CO')}`, left + 260, y, { lineBreak: false });
      doc.moveDown(0.6);
    }
  } else if (category === 'ventas_producto') {
    if (!data.length) { emptyState(doc, 'Sin ventas registradas en este rango de fechas.'); return; }
    tableHeader(doc, [['Producto', left], ['Unidades', left + 260], ['Ingresos', left + 350]]);
    for (const row of data) {
      ensureSpace(doc, 20);
      const y = doc.y;
      doc.fontSize(10).font('Helvetica').fillColor('#333')
        .text(stripEmoji(row.producto).slice(0, 45), left, y, { width: 250, lineBreak: false })
        .text(String(row.unidades), left + 260, y, { lineBreak: false })
        .text(`$${Number(row.ingresos).toLocaleString('es-CO')}`, left + 350, y, { lineBreak: false });
      doc.moveDown(0.6);
    }
  } else if (category === 'empleados') {
    if (!data.length) { emptyState(doc, 'Sin entregas registradas en este rango de fechas.'); return; }
    tableHeader(doc, [['Empleado', left], ['Entregados', left + 260], ['Min. promedio', left + 350]]);
    for (const row of data) {
      ensureSpace(doc, 20);
      const y = doc.y;
      doc.fontSize(10).font('Helvetica').fillColor('#333')
        .text(stripEmoji(row.nombre).slice(0, 40), left, y, { width: 250, lineBreak: false })
        .text(String(row.entregados), left + 260, y, { lineBreak: false })
        .text(String(row.minutos_prom || 0), left + 350, y, { lineBreak: false });
      doc.moveDown(0.6);
    }
  } else if (category === 'clientes') {
    doc.fontSize(10).font('Helvetica-Bold').fillColor('#444')
       .text(`Clientes nuevos en el rango: ${data.nuevos}     Clientes recurrentes: ${data.recurrentes}`);
    doc.moveDown(0.5);
    if (!data.clientes.length) { emptyState(doc, 'Sin clientes con pedidos en este rango de fechas.'); return; }
    tableHeader(doc, [['Cliente', left], ['Pedidos', left + 260], ['Gastado', left + 350]]);
    for (const c of data.clientes) {
      ensureSpace(doc, 20);
      const y = doc.y;
      doc.fontSize(10).font('Helvetica').fillColor('#333')
        .text(stripEmoji(c.name || c.phone || 'N/A').slice(0, 40), left, y, { width: 250, lineBreak: false })
        .text(String(c.pedidos), left + 260, y, { lineBreak: false })
        .text(`$${Number(c.gastado).toLocaleString('es-CO')}`, left + 350, y, { lineBreak: false });
      doc.moveDown(0.6);
    }
  }
  doc.moveDown(0.5);
}

async function generateRangeReportPDF(fromISO, toISO, categories) {
  const cats = (categories && categories.length ? categories : CATEGORIES).filter(c => CATEGORIES.includes(c));
  const db = getDB();
  const fromLabel = new Date(fromISO).toLocaleDateString('es-CO', { timeZone: TZ, day: '2-digit', month: 'long', year: 'numeric' });
  const toLabel   = new Date(toISO).toLocaleDateString('es-CO',   { timeZone: TZ, day: '2-digit', month: 'long', year: 'numeric' });

  const reportsDir = process.env.REPORTS_DIR || path.join(__dirname, '../../reports');
  if (!fs.existsSync(reportsDir)) fs.mkdirSync(reportsDir, { recursive: true });

  // Nombre y portada identifican la categoria exacta -- el dashboard pide
  // un archivo por categoria elegida, nunca deben pisarse ni confundirse
  // entre si en la carpeta de descargas.
  const slug = cats.map(c => CATEGORY_SLUGS[c]).join('_');
  const title = cats.length === 1 ? CATEGORY_LABELS[cats[0]] : 'Reporte de Datos';
  const filename = `${slug}-${fromISO}_a_${toISO}.pdf`;
  const filepath = path.join(reportsDir, filename);
  const doc = new PDFDocument({ margin: 40, size: 'A4', bufferPages: true });
  const stream = fs.createWriteStream(filepath);
  doc.pipe(stream);

  drawCover(doc, title, `${fromLabel}  —  ${toLabel}`);

  for (const cat of cats) {
    let data;
    if (cat === 'resumen') data = getFinancialSummary(db, fromISO, toISO);
    else if (cat === 'ventas_dia') data = getSalesByDay(db, fromISO, toISO);
    else if (cat === 'ventas_producto') data = getSalesByProduct(db, fromISO, toISO);
    else if (cat === 'empleados') data = getEmployeePerformance(db, fromISO, toISO);
    else if (cat === 'clientes') data = getCustomerReport(db, fromISO, toISO);
    renderCategorySection(doc, cat, data);
  }

  paginate(doc, filename);
  doc.end();
  await new Promise((resolve, reject) => {
    stream.on('finish', resolve);
    stream.on('error', reject);
  });

  logger.info({ filepath, categories: cats }, '[PDF] reporte por categorias generado');
  return filepath;
}

module.exports = {
  generateDailyPDF, generateRangeReportPDF, CATEGORIES, CATEGORY_LABELS, CATEGORY_SLUGS,
  getFinancialSummary, getSalesByDay, getSalesByProduct, getEmployeePerformance, getCustomerReport,
};
