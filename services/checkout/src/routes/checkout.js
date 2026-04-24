const express = require('express');
const { body, param, validationResult } = require('express-validator');
const { v4: uuidv4 } = require('uuid');
const { connectDB } = require('../db/client');
const { authenticate } = require('../middleware/auth');
const { publishInvoiceEvent } = require('../sqs/publisher');
const { logger } = require('../middleware/logger');

const router = express.Router();

function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
  next();
}

router.use(authenticate);

// POST /api/v1/checkout
router.post('/',
  body('items').isArray({ min: 1 }),
  body('items.*.productId').isUUID(),
  body('items.*.quantity').isInt({ min: 1 }),
  body('items.*.price').isFloat({ min: 0 }),
  body('items.*.name').trim().notEmpty(),
  body('shippingAddress').isObject(),
  body('shippingAddress.street').trim().notEmpty(),
  body('shippingAddress.city').trim().notEmpty(),
  body('shippingAddress.country').trim().isLength({ min: 2, max: 2 }),
  body('currency').optional().isIn(['USD', 'EUR']),
  validate,
  async (req, res, next) => {
    const db = connectDB();
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      const { items, shippingAddress, currency = 'USD' } = req.body;
      const total = items.reduce((sum, i) => sum + i.price * i.quantity, 0);
      const orderId = uuidv4();

      // Verify stock and lock rows
      for (const item of items) {
        const { rows } = await client.query(
          'SELECT stock_quantity FROM products WHERE id = $1 AND deleted_at IS NULL FOR UPDATE',
          [item.productId]
        );
        if (!rows.length) throw Object.assign(new Error(`Product ${item.productId} not found`), { status: 404 });
        if (rows[0].stock_quantity < item.quantity) {
          throw Object.assign(new Error(`Insufficient stock for product ${item.productId}`), { status: 409 });
        }
        await client.query(
          'UPDATE products SET stock_quantity = stock_quantity - $1 WHERE id = $2',
          [item.quantity, item.productId]
        );
      }

      // Create order
      const { rows: [order] } = await client.query(
        `INSERT INTO orders (id, customer_id, customer_email, items, total, currency, shipping_address, status)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending')
         RETURNING *`,
        [orderId, req.user.sub, req.user.email, JSON.stringify(items), Math.round(total * 100) / 100, currency, JSON.stringify(shippingAddress)]
      );

      await client.query('COMMIT');

      // Publish async invoice event (non-blocking)
      publishInvoiceEvent(order).catch((err) =>
        logger.error({ msg: 'Failed to publish invoice event', orderId: order.id, err })
      );

      res.status(201).json({
        orderId: order.id,
        status: order.status,
        total: order.total,
        currency: order.currency,
        createdAt: order.created_at,
      });
    } catch (err) {
      await client.query('ROLLBACK');
      next(err);
    } finally {
      client.release();
    }
  }
);

// GET /api/v1/checkout/orders
router.get('/orders', async (req, res, next) => {
  try {
    const db = connectDB();
    const { rows } = await db.query(
      'SELECT id, total, currency, status, created_at FROM orders WHERE customer_id = $1 ORDER BY created_at DESC LIMIT 50',
      [req.user.sub]
    );
    res.json({ orders: rows });
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/checkout/orders/:orderId
router.get('/orders/:orderId',
  param('orderId').isUUID(),
  validate,
  async (req, res, next) => {
    try {
      const db = connectDB();
      const { rows } = await db.query(
        'SELECT * FROM orders WHERE id = $1 AND customer_id = $2',
        [req.params.orderId, req.user.sub]
      );
      if (!rows.length) return res.status(404).json({ error: 'Order not found' });
      res.json(rows[0]);
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
