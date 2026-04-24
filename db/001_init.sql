-- ShopCloud Database Schema
-- Run as: psql -U shopcloud_user -d shopcloud -f 001_init.sql

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- for full-text search on products

-- Products table
CREATE TABLE IF NOT EXISTS products (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name            VARCHAR(255)        NOT NULL,
  description     TEXT                NOT NULL,
  price           NUMERIC(10, 2)      NOT NULL CHECK (price >= 0),
  category        VARCHAR(100)        NOT NULL,
  stock_quantity  INTEGER             NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
  image_url       TEXT,
  created_at      TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
  deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_products_category ON products(category) WHERE deleted_at IS NULL;
CREATE INDEX idx_products_name_trgm ON products USING GIN (name gin_trgm_ops);
CREATE INDEX idx_products_created_at ON products(created_at DESC) WHERE deleted_at IS NULL;

-- Orders table
CREATE TABLE IF NOT EXISTS orders (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id      VARCHAR(255)       NOT NULL,
  customer_email   VARCHAR(255)       NOT NULL,
  items            JSONB              NOT NULL,
  total            NUMERIC(10, 2)     NOT NULL CHECK (total >= 0),
  currency         VARCHAR(3)         NOT NULL DEFAULT 'USD',
  shipping_address JSONB              NOT NULL,
  status           VARCHAR(50)        NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','processing','shipped','completed','cancelled')),
  created_at       TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ        NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_products_updated_at
  BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_orders_updated_at
  BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Seed some sample products
INSERT INTO products (name, description, price, category, stock_quantity) VALUES
  ('Wireless Headphones Pro', 'Premium noise-cancelling wireless headphones with 30h battery', 149.99, 'Electronics', 100),
  ('Ergonomic Office Chair', 'Adjustable lumbar support, breathable mesh, 5-year warranty', 349.99, 'Furniture', 50),
  ('Running Shoes X500', 'Lightweight, cushioned sole, available in multiple colors', 89.99, 'Footwear', 200),
  ('Stainless Steel Water Bottle', '1L insulated, keeps cold 24h, hot 12h, BPA-free', 29.99, 'Accessories', 500),
  ('Mechanical Keyboard TKL', 'Tenkeyless, Cherry MX Red switches, RGB backlit', 129.99, 'Electronics', 75)
ON CONFLICT DO NOTHING;
