require('dotenv').config();
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const client = require('prom-client');
const { logger } = require('./middleware/logger');
const cartRouter = require('./routes/cart');
const { getRedis } = require('./redis/client');

const app = express();
const PORT = process.env.PORT || 3002;

const register = new client.Registry();
client.collectDefaultMetrics({ register });

app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(',') || '*' }));
app.use(express.json());
app.use(morgan('combined', { stream: { write: (msg) => logger.info(msg.trim()) } }));

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'cart' }));
app.get('/ready', async (req, res) => {
  try {
    await getRedis().ping();
    res.json({ status: 'ready' });
  } catch {
    res.status(503).json({ status: 'not ready' });
  }
});
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.use('/api/v1/cart', cartRouter);

app.use((err, req, res, next) => {
  logger.error({ err, path: req.path });
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

app.listen(PORT, () => logger.info(`Cart service running on port ${PORT}`));

module.exports = app;
