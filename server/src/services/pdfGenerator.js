const PDFDocument = require('pdfkit');
const fs = require('fs');
const path = require('path');
const { getDB } = require('../db/database');

function formatDate(iso) {
  if (!iso) return 'N/A';
  return new Date(iso).toLocaleString('es-CO', {
    timeZone: 'America/Bogota', day: '2-digit', month: '2-digit',
    year: 'numeric', hour: '2-digit', minute: '2-digit'
  });
}

async function generateDailyPDF() {
  const db = getDB();
  const todayISO = new Date().toISOString().split('T')[0];

  const orders = db.prepare(`
    SELECT o.*, c.phone, c.name as customer_name,
           u.display_name as delivered_by_name
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN users     u ON o.claimed_by  = u.id
    WHERE o.status IN ('delivered','entregado') AND date(o.delivered_at)=?
    ORDER BY o.delivered_at ASC
  `).all(todayISO);

  // Attach order_items for multi-product orders
  const itemsStmt = db.prepare('SELECT * FROM order_items WHERE order_id=?');
  orders.forEach(o => { o.items = itemsStmt.all(o.id); });

  const reportsDir = path.join(__dirname, '../../reports');
  if (!fs.existsSync(reportsDir)) fs.mkdirSync(reportsDir, { recursive: true });

  const filepath = path.join(reportsDir, `pedidos-${todayISO}.pdf`);
  const doc = new PDFDocument({ margin: 40, size: 'A4' });
  const stream = fs.createWriteStream(filepath);
  doc.pipe(stream);

  doc.fontSize(20).fillColor('#2E7D32').text('Reporte de Pedidos Entregados', { align: 'center' });
  doc.fontSize(12).fillColor('#666')
    .text(`Fecha: ${formatDate(new Date().toISOString())}`, { align: 'center' })
    .text(`Total pedidos: ${orders.length}`, { align: 'center' });
  doc.moveDown(1.5);

  if (!orders.length) {
    doc.fontSize(14).fillColor('#333').text('No hubo pedidos entregados hoy.', { align: 'center' });
  } else {
    orders.forEach((order, idx) => {
      if (doc.y > 680) doc.addPage();
      const productLabel = order.items?.length > 1
        ? order.items.map(it => `${it.quantity}x ${it.product_name}`).join(', ')
        : order.product_name;
      doc.fontSize(13).fillColor('#1B5E20').text(`#${idx + 1} — ${productLabel}`);
      doc.fontSize(10).fillColor('#333');
      [
        ['Cliente', order.customer_name || order.phone || 'N/A'],
        ['Teléfono', order.phone || 'N/A'],
        ['Entregó', order.delivered_by_name || 'N/A'],
        ['Dirección', order.delivery_address || 'N/A'],
        ['Precio', order.product_price ? `$${Number(order.product_price).toLocaleString('es-CO')}` : 'N/A'],
        ['Fiado', order.is_fiado ? 'SÍ' : 'No'],
        ['Solicitado', formatDate(order.requested_at)],
        ['Entregado', formatDate(order.delivered_at)],
        ['Comentario', order.comment || '—'],
      ].forEach(([label, value]) => {
        doc.fillColor('#555').text(`${label}: `, { continued: true }).fillColor('#333').text(value);
      });
      doc.moveDown(1);
    });
  }

  doc.end();
  await new Promise((resolve, reject) => { stream.on('finish', resolve); stream.on('error', reject); });

  if (orders.length) {
    const placeholders = orders.map(() => '?').join(',');
    db.prepare(`UPDATE orders SET pdf_exported=1 WHERE id IN (${placeholders})`).run(...orders.map(o => o.id));
    db.prepare(`DELETE FROM orders WHERE status='delivered' AND pdf_exported=1 AND date(delivered_at)=?`).run(todayISO);
  }

  console.log(`PDF: ${filepath} (${orders.length} pedidos)`);
  return filepath;
}

module.exports = { generateDailyPDF };
