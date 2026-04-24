const express = require('express');
const { body, param, query, validationResult } = require('express-validator');
const { connectDB } = require('../db/client');
const { authenticate, requireAdmin } = require('../middleware/auth');

const router = express.Router();

function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
  next();
}

// GET /api/v1/products
router.get('/',
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
  query('category').optional().isString(),
  query('search').optional().isString().trim(),
  validate,
  async (req, res, next) => {
    try {
      const db = connectDB();
      const page = parseInt(req.query.page || '1');
      const limit = parseInt(req.query.limit || '20');
      const offset = (page - 1) * limit;

      let whereClause = 'WHERE deleted_at IS NULL';
      const params = [];

      if (req.query.category) {
        params.push(req.query.category);
        whereClause += ` AND category = $${params.length}`;
      }
      if (req.query.search) {
        params.push(`%${req.query.search}%`);
        whereClause += ` AND (name ILIKE $${params.length} OR description ILIKE $${params.length})`;
      }

      params.push(limit, offset);
      const { rows } = await db.query(
        `SELECT id, name, description, price, category, stock_quantity, image_url, created_at
         FROM products ${whereClause}
         ORDER BY created_at DESC
         LIMIT $${params.length - 1} OFFSET $${params.length}`,
        params
      );

      const countParams = params.slice(0, -2);
      const { rows: countRows } = await db.query(
        `SELECT COUNT(*) FROM products ${whereClause}`,
        countParams
      );

      res.json({
        data: rows,
        pagination: { page, limit, total: parseInt(countRows[0].count) },
      });
    } catch (err) {
      next(err);
    }
  }
);

// GET /api/v1/products/:id
router.get('/:id',
  param('id').isUUID(),
  validate,
  async (req, res, next) => {
    try {
      const db = connectDB();
      const { rows } = await db.query(
        'SELECT * FROM products WHERE id = $1 AND deleted_at IS NULL',
        [req.params.id]
      );
      if (!rows.length) return res.status(404).json({ error: 'Product not found' });
      res.json(rows[0]);
    } catch (err) {
      next(err);
    }
  }
);

// POST /api/v1/products (admin only)
router.post('/',
  authenticate, requireAdmin,
  body('name').trim().notEmpty().isLength({ max: 255 }),
  body('description').trim().notEmpty(),
  body('price').isFloat({ min: 0 }),
  body('category').trim().notEmpty(),
  body('stock_quantity').isInt({ min: 0 }),
  body('image_url').optional().isURL(),
  validate,
  async (req, res, next) => {
    try {
      const db = connectDB();
      const { name, description, price, category, stock_quantity, image_url } = req.body;
      const { rows } = await db.query(
        `INSERT INTO products (name, description, price, category, stock_quantity, image_url)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [name, description, price, category, stock_quantity, image_url]
      );
      res.status(201).json(rows[0]);
    } catch (err) {
      next(err);
    }
  }
);

// PUT /api/v1/products/:id (admin only)
router.put('/:id',
  authenticate, requireAdmin,
  param('id').isUUID(),
  body('name').optional().trim().notEmpty().isLength({ max: 255 }),
  body('price').optional().isFloat({ min: 0 }),
  body('stock_quantity').optional().isInt({ min: 0 }),
  validate,
  async (req, res, next) => {
    try {
      const db = connectDB();
      const fields = [];
      const values = [];
      const allowed = ['name', 'description', 'price', 'category', 'stock_quantity', 'image_url'];
      allowed.forEach((field) => {
        if (req.body[field] !== undefined) {
          values.push(req.body[field]);
          fields.push(`${field} = $${values.length}`);
        }
      });
      if (!fields.length) return res.status(400).json({ error: 'No fields to update' });
      values.push(req.params.id);
      const { rows } = await db.query(
        `UPDATE products SET ${fields.join(', ')}, updated_at = NOW() WHERE id = $${values.length} AND deleted_at IS NULL RETURNING *`,
        values
      );
      if (!rows.length) return res.status(404).json({ error: 'Product not found' });
      res.json(rows[0]);
    } catch (err) {
      next(err);
    }
  }
);

// DELETE /api/v1/products/:id (admin only, soft delete)
router.delete('/:id',
  authenticate, requireAdmin,
  param('id').isUUID(),
  validate,
  async (req, res, next) => {
    try {
      const db = connectDB();
      const { rows } = await db.query(
        'UPDATE products SET deleted_at = NOW() WHERE id = $1 AND deleted_at IS NULL RETURNING id',
        [req.params.id]
      );
      if (!rows.length) return res.status(404).json({ error: 'Product not found' });
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
