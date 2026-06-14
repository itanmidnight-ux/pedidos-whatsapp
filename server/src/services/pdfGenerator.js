'use strict';
const PDFDocument = require('pdfkit');
const fs   = require('fs');
const path = require('path');
const { getDB } = require('../db/database');

const TZ = 'America/Bogota';

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

function sectionHeader(doc, title) {
  doc.moveDown(0.5);
  doc.rect(doc.page.margins.left, doc.y, doc.page.width - doc.page.margins.left - doc.page.margins.right, 22)
     .fill('#1B5E20');
  doc.fillColor('white').fontSize(12).font('Helvetica-Bold')
     .text(title, doc.page.margins.left + 8, doc.y - 18, { lineBreak: false });
  doc.font('Helvetica').fillColor('#333');
  doc.moveDown(1.2);
}

function divider(doc) {
  doc.moveTo(doc.page.margins.left, doc.y)
     .lineTo(doc.page.width - doc.page.margins.right, doc.y)
     .strokeColor('#cccccc').lineWidth(0.5).stroke();
  doc.moveDown(0.4);
}

async function generateDailyPDF() {
  const db = getDB();
  const now = new Date();
  const todayISO = now.toISOString().split('T')[0];
  const todayLabel = now.toLocaleDateString('es-CO', {
    timeZone: TZ, weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
  });

  // ── Pedidos del día ───────────────────────────────────────────
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

  // ── Chats del día ─────────────────────────────────────────────
  const messages = db.prepare(`
    SELECT m.*, COALESCE(c.name, m.customer_name) AS display_name
    FROM messages m
    LEFT JOIN customers c ON c.phone = m.phone
    WHERE date(m.created_at, 'localtime') = ?
    ORDER BY m.phone, m.created_at ASC
  `).all(todayISO);

  // Agrupar por teléfono
  const chatsByPhone = {};
  for (const msg of messages) {
    if (!chatsByPhone[msg.phone]) {
      chatsByPhone[msg.phone] = { displayName: msg.display_name || msg.phone, msgs: [] };
    }
    chatsByPhone[msg.phone].msgs.push(msg);
  }
  const chatPhones = Object.keys(chatsByPhone);

  // ── Crear directorio y archivo ────────────────────────────────
  const reportsDir = path.join(__dirname, '../../reports');
  if (!fs.existsSync(reportsDir)) fs.mkdirSync(reportsDir, { recursive: true });

  const filename = `registro-${todayISO}.pdf`;
  const filepath = path.join(reportsDir, filename);
  const doc = new PDFDocument({ margin: 40, size: 'A4', bufferPages: true });
  const stream = fs.createWriteStream(filepath);
  doc.pipe(stream);

  // ── Portada ───────────────────────────────────────────────────
  doc.rect(0, 0, doc.page.width, 120).fill('#0D4F1C');
  doc.fillColor('white').fontSize(22).font('Helvetica-Bold')
     .text('CONCENTRADOS MONSERRATH', 40, 30, { align: 'center' });
  doc.fontSize(14).font('Helvetica')
     .text('Registro Diario — Chats y Pedidos', { align: 'center' });
  doc.fontSize(11).fillColor('#a5d6a7')
     .text(todayLabel.charAt(0).toUpperCase() + todayLabel.slice(1), { align: 'center' });
  doc.moveDown(3.5);

  // Resumen ejecutivo
  doc.fillColor('#333').fontSize(11).font('Helvetica');
  const totalIngresos = orders.reduce((s, o) => s + (Number(o.product_price) || 0), 0);
  const totalFiado    = orders.filter(o => o.is_fiado).length;

  const summaryData = [
    ['📦 Pedidos entregados', `${orders.length}`],
    ['💰 Ingresos del día',   `$${totalIngresos.toLocaleString('es-CO')}`],
    ['📋 Pedidos fiados',     `${totalFiado}`],
    ['💬 Conversaciones',     `${chatPhones.length}`],
    ['📨 Mensajes totales',   `${messages.length}`],
  ];

  doc.fontSize(13).font('Helvetica-Bold').fillColor('#1B5E20')
     .text('Resumen del día', { underline: false });
  doc.moveDown(0.3);

  for (const [label, val] of summaryData) {
    doc.fontSize(11).font('Helvetica').fillColor('#555')
       .text(label + ': ', { continued: true })
       .font('Helvetica-Bold').fillColor('#111').text(val);
  }

  // ── SECCIÓN 1: PEDIDOS ────────────────────────────────────────
  doc.addPage();
  sectionHeader(doc, `📦  PEDIDOS ENTREGADOS  (${orders.length})`);

  if (!orders.length) {
    doc.fontSize(12).fillColor('#777').text('No hubo pedidos entregados hoy.', { align: 'center' });
  } else {
    orders.forEach((order, idx) => {
      if (doc.y > 680) doc.addPage();
      const productLabel = order.items?.length > 1
        ? order.items.map(it => `${it.quantity}x ${it.product_name}`).join(', ')
        : order.product_name;

      doc.fontSize(12).font('Helvetica-Bold').fillColor('#1B5E20')
         .text(`#${idx + 1}  ${productLabel}`);
      doc.font('Helvetica').fontSize(10).fillColor('#333');
      [
        ['Cliente',    order.customer_name || order.phone || 'N/A'],
        ['Teléfono',   order.phone || 'N/A'],
        ['Entregó',    order.delivered_by_name || 'N/A'],
        ['Dirección',  order.delivery_address || 'N/A'],
        ['Precio',     order.product_price ? `$${Number(order.product_price).toLocaleString('es-CO')}` : 'N/A'],
        ['Fiado',      order.is_fiado ? '✓ SÍ' : 'No'],
        ['Solicitado', fmt(order.requested_at)],
        ['Entregado',  fmt(order.delivered_at)],
        ['Mensaje WA', order.wa_message || '—'],
      ].forEach(([lbl, val]) => {
        doc.fillColor('#888').text(`${lbl}: `, { continued: true })
           .fillColor('#222').text(String(val).slice(0, 120));
      });
      divider(doc);
    });
  }

  // ── SECCIÓN 2: CHATS ──────────────────────────────────────────
  doc.addPage();
  sectionHeader(doc, `💬  REGISTRO DE CHATS  (${chatPhones.length} conversaciones)`);

  if (!chatPhones.length) {
    doc.fontSize(12).fillColor('#777').text('No hubo mensajes hoy.', { align: 'center' });
  } else {
    for (const phone of chatPhones) {
      const chat = chatsByPhone[phone];
      if (doc.y > 650) doc.addPage();

      doc.fontSize(12).font('Helvetica-Bold').fillColor('#1B5E20')
         .text(`${chat.displayName}`);
      doc.fontSize(9).font('Helvetica').fillColor('#888')
         .text(phone.length === 12 && phone.startsWith('57')
           ? `+57 ${phone.substring(2,5)} ${phone.substring(5,8)} ${phone.substring(8)}`
           : `+${phone}`);
      doc.moveDown(0.3);

      for (const msg of chat.msgs) {
        if (doc.y > 720) doc.addPage();
        const isOut = msg.direction === 'outbound';
        const tag   = isOut ? '[Bot/Admin]' : '[Cliente]';
        const color = isOut ? '#1565C0' : '#333';
        const time  = fmtTime(msg.created_at);

        doc.fontSize(9).font('Helvetica-Bold').fillColor(color)
           .text(`${time}  ${tag}  `, { continued: true })
           .font('Helvetica').fillColor('#222')
           .text(
             msg.media_type === 'audio' ? '🎵 Mensaje de voz'
           : msg.media_type === 'image' ? '📷 Imagen'
           : String(msg.content || '').slice(0, 300),
           { lineBreak: true }
           );
      }
      divider(doc);
    }
  }

  // Numeración de páginas
  const pages = doc.bufferedPageRange();
  for (let i = 0; i < pages.count; i++) {
    doc.switchToPage(i);
    doc.fontSize(8).fillColor('#aaa')
       .text(`Página ${i + 1} de ${pages.count}  •  ${filename}`,
         doc.page.margins.left, doc.page.height - 30,
         { align: 'center', lineBreak: false });
  }

  doc.end();
  await new Promise((resolve, reject) => {
    stream.on('finish', resolve);
    stream.on('error', reject);
  });

  // Marcar pedidos exportados
  if (orders.length) {
    const placeholders = orders.map(() => '?').join(',');
    db.prepare(`UPDATE orders SET pdf_exported=1 WHERE id IN (${placeholders})`)
      .run(...orders.map(o => o.id));
  }

  console.log(`[PDF] ${filepath} — ${orders.length} pedidos, ${chatPhones.length} chats`);
  return filepath;
}

module.exports = { generateDailyPDF };
