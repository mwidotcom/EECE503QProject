require('dotenv').config();
const express = require('express');
const helmet = require('helmet');
const morgan = require('morgan');
const client = require('prom-client');
const { logger } = require('./middleware/logger');
const adminRouter = require('./routes/admin');
const { connectDB } = require('./db/client');

const app = express();
const PORT = process.env.PORT || 3005;

const register = new client.Registry();
client.collectDefaultMetrics({ register });

// Admin service: no CORS (internal ALB only), strict helmet
app.use(helmet());
app.use(express.json());
app.use(morgan('combined', { stream: { write: (msg) => logger.info(msg.trim()) } }));

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'admin' }));
app.get('/ready', async (req, res) => {
  try {
    await connectDB().query('SELECT 1');
    res.json({ status: 'ready' });
  } catch {
    res.status(503).json({ status: 'not ready' });
  }
});
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.use('/api/v1/admin', adminRouter);

app.use((err, req, res, next) => {
  logger.error({ err, path: req.path });
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

connectDB()
  .then(() => app.listen(PORT, () => logger.info(`Admin service running on port ${PORT}`)))
  .catch((err) => { logger.error(err); process.exit(1); });

module.exports = app;
