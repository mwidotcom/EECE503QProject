require('dotenv').config();
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const client = require('prom-client');
const { logger } = require('./middleware/logger');
const productsRouter = require('./routes/products');
const { connectDB } = require('./db/client');

const app = express();
const PORT = process.env.PORT || 3001;

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(',') || '*' }));
app.use(express.json({ limit: '10mb' }));
app.use(morgan('combined', { stream: { write: (msg) => logger.info(msg.trim()) } }));

// Request duration middleware
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    end({ method: req.method, route: req.route?.path || req.path, status_code: res.statusCode });
  });
  next();
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'catalog', timestamp: new Date().toISOString() }));
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

app.use('/api/v1/products', productsRouter);

app.use((err, req, res, next) => {
  logger.error({ err, path: req.path, method: req.method });
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

connectDB()
  .then(() => {
    app.listen(PORT, () => logger.info(`Catalog service running on port ${PORT}`));
  })
  .catch((err) => {
    logger.error('Failed to connect to database', err);
    process.exit(1);
  });

module.exports = app;
