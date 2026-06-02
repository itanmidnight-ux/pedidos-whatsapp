const cron = require('node-cron');
const { generateDailyPDF } = require('./pdfGenerator');

function schedulePDFJob() {
  cron.schedule('59 23 * * *', async () => {
    console.log('Generando PDF diario...');
    try {
      const path = await generateDailyPDF();
      console.log('PDF completado:', path);
    } catch (err) {
      console.error('Error PDF:', err.message);
    }
  }, { timezone: 'America/Bogota' });
  console.log('PDF scheduler activo (23:59 diario)');
}

module.exports = { schedulePDFJob };
