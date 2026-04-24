const Redis = require('ioredis');
const { logger } = require('../middleware/logger');

let redisClient;

function getRedis() {
  if (!redisClient) {
    redisClient = new Redis({
      host: process.env.REDIS_HOST,
      port: parseInt(process.env.REDIS_PORT || '6379'),
      password: process.env.REDIS_PASSWORD,
      tls: process.env.REDIS_TLS === 'true' ? {} : undefined,
      retryStrategy: (times) => Math.min(times * 50, 2000),
      maxRetriesPerRequest: 3,
    });

    redisClient.on('connect', () => logger.info('Redis connected'));
    redisClient.on('error', (err) => logger.error('Redis error', err));
  }
  return redisClient;
}

const CART_TTL = 7 * 24 * 60 * 60; // 7 days in seconds

async function getCart(userId) {
  const data = await getRedis().get(`cart:${userId}`);
  return data ? JSON.parse(data) : { items: [], updatedAt: null };
}

async function setCart(userId, cart) {
  cart.updatedAt = new Date().toISOString();
  await getRedis().setex(`cart:${userId}`, CART_TTL, JSON.stringify(cart));
  return cart;
}

async function deleteCart(userId) {
  await getRedis().del(`cart:${userId}`);
}

module.exports = { getRedis, getCart, setCart, deleteCart };
