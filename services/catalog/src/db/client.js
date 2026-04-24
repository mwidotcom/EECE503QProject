const { Pool } = require('pg');
const { logger } = require('../middleware/logger');

let pool;

function connectDB() {
  if (!pool) {
    pool = new Pool({
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT || '5432'),
      database: process.env.DB_NAME || 'shopcloud',
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
      ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: true } : false,
    });

    pool.on('error', (err) => logger.error('Unexpected DB pool error', err));
    logger.info('Database pool initialized');
  }
  return pool;
}

module.exports = { connectDB };
