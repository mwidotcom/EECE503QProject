const request = require('supertest');

// Mock DB before requiring app
jest.mock('../src/db/client', () => ({
  connectDB: jest.fn().mockReturnValue({
    query: jest.fn(),
  }),
}));

const { connectDB } = require('../src/db/client');
const app = require('../src/index');

describe('GET /health', () => {
  it('returns healthy status', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('healthy');
  });
});

describe('GET /api/v1/products', () => {
  it('returns paginated products', async () => {
    const mockDB = connectDB();
    mockDB.query
      .mockResolvedValueOnce({ rows: [{ id: 'uuid-1', name: 'Product 1', price: 9.99 }] })
      .mockResolvedValueOnce({ rows: [{ count: '1' }] });

    const res = await request(app).get('/api/v1/products');
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.pagination).toBeDefined();
  });

  it('returns 404 for unknown product', async () => {
    const mockDB = connectDB();
    mockDB.query.mockResolvedValueOnce({ rows: [] });
    const res = await request(app).get('/api/v1/products/00000000-0000-0000-0000-000000000000');
    expect(res.status).toBe(404);
  });
});
