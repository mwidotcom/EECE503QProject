const express = require('express');
const { query, param, validationResult } = require('express-validator');
const { connectDB } = require('../db/client');
const { authenticate } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
  next();
}

// GET /api/v1/admin/orders
router.get('/orders',
  query('status').optional().isIn(['pending', 'processing', 'shipped', 'completed', 'cancelled']),
  query('page').optional().isInt({ min: 1 }),
  validate,
  async (req, res, next) => {
    try {
      const db = connectDB();
      const page = parseInt(req.query.page || '1');
      const limit = 50;
      const offset = (page - 1) * limit;
      const params = [limit, offset];
      let where = '';
      if (req.query.status) {
        params.unshift(req.query.status);
        where = `WHERE status = $1`;
      }
      const { rows } = await db.query(
        `SELECT id, customer_id, customer_email, total, currency, status, created_at
         FROM orders ${where}
         ORDER BY created_at DESC
         LIMIT $${params.length - 1} OFFSET $${params.length}`,
        params
      );
      res.json({ orders: rows, page, limit });
    } catch (err) {
      next(err);
    }
  }
);

// PATCH /api/v1/admin/orders/:orderId/status
router.patch('/orders/:orderId/status',
  param('orderId').isUUID(),
  validate,
  async (req, res, next) => {
    try {
      const { status } = req.body;
      const validStatuses = ['processing', 'shipped', 'completed', 'cancelled'];
      if (!validStatuses.includes(status)) {
        return res.status(400).json({ error: `Status must be one of: ${validStatuses.join(', ')}` });
      }
      const db = connectDB();
      const { rows } = await db.query(
        `UPDATE orders SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING id, status, updated_at`,
        [status, req.params.orderId]
      );
      if (!rows.length) return res.status(404).json({ error: 'Order not found' });
      res.json(rows[0]);
    } catch (err) {
      next(err);
    }
  }
);

// GET /api/v1/admin/metrics/summary
router.get('/metrics/summary', async (req, res, next) => {
  try {
    const db = connectDB();
    const [ordersRes, revenueRes, productsRes] = await Promise.all([
      db.query(`SELECT COUNT(*), status FROM orders GROUP BY status`),
      db.query(`SELECT SUM(total) as total_revenue, COUNT(*) as total_orders FROM orders WHERE status = 'completed'`),
      db.query(`SELECT COUNT(*) as total_products, SUM(stock_quantity) as total_stock FROM products WHERE deleted_at IS NULL`),
    ]);
    res.json({
      orders: ordersRes.rows,
      revenue: revenueRes.rows[0],
      inventory: productsRes.rows[0],
    });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
