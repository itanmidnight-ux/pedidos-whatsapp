'use strict';
const app = require('./app');
const { initDB } = require('./db/database');
const { schedulePDFJob } = require('./services/pdfScheduler');
const logger = require('./utils/logger');

const PORT = process.env.PORT || 3000;
initDB().then(() => {
  schedulePDFJob();
  app.listen(PORT, async () => {
    logger.info(`Servidor corriendo en puerto ${PORT}`);
    if (process.env.BOT_ENABLED === 'true') {
      const { initBot } = require('./services/waBot');
      await initBot().catch(e => logger.error({ err: e.message }, '[bot] init error'));
    }
  });
}).catch(err => { logger.error({ err }, 'Error iniciando servidor'); process.exit(1); });
