const express = require('express');
const { body, param, validationResult } = require('express-validator');
const { getCart, setCart, deleteCart } = require('../redis/client');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
  next();
}

// All cart routes require authentication
router.use(authenticate);

// GET /api/v1/cart
router.get('/', async (req, res, next) => {
  try {
    const cart = await getCart(req.user.sub);
    const total = cart.items.reduce((sum, item) => sum + item.price * item.quantity, 0);
    res.json({ ...cart, total: Math.round(total * 100) / 100 });
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/cart/items
router.post('/items',
  body('productId').isUUID(),
  body('quantity').isInt({ min: 1, max: 100 }),
  body('name').trim().notEmpty(),
  body('price').isFloat({ min: 0 }),
  validate,
  async (req, res, next) => {
    try {
      const cart = await getCart(req.user.sub);
      const { productId, quantity, name, price } = req.body;

      const existing = cart.items.find((i) => i.productId === productId);
      if (existing) {
        existing.quantity = Math.min(existing.quantity + quantity, 100);
      } else {
        cart.items.push({ productId, quantity, name, price });
      }

      const updated = await setCart(req.user.sub, cart);
      res.status(201).json(updated);
    } catch (err) {
      next(err);
    }
  }
);

// PUT /api/v1/cart/items/:productId
router.put('/items/:productId',
  param('productId').isUUID(),
  body('quantity').isInt({ min: 0, max: 100 }),
  validate,
  async (req, res, next) => {
    try {
      const cart = await getCart(req.user.sub);
      const { quantity } = req.body;
      const idx = cart.items.findIndex((i) => i.productId === req.params.productId);
      if (idx === -1) return res.status(404).json({ error: 'Item not in cart' });

      if (quantity === 0) {
        cart.items.splice(idx, 1);
      } else {
        cart.items[idx].quantity = quantity;
      }

      const updated = await setCart(req.user.sub, cart);
      res.json(updated);
    } catch (err) {
      next(err);
    }
  }
);

// DELETE /api/v1/cart/items/:productId
router.delete('/items/:productId',
  param('productId').isUUID(),
  validate,
  async (req, res, next) => {
    try {
      const cart = await getCart(req.user.sub);
      cart.items = cart.items.filter((i) => i.productId !== req.params.productId);
      await setCart(req.user.sub, cart);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  }
);

// DELETE /api/v1/cart (clear entire cart)
router.delete('/', async (req, res, next) => {
  try {
    await deleteCart(req.user.sub);
    res.status(204).send();
  } catch (err) {
    next(err);
  }
});

module.exports = router;
