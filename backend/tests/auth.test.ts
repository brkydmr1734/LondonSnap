import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../src/app';
import { prisma } from '../src/lib/prisma';
import { redis } from '../src/lib/redis';

describe('Auth API', () => {
  beforeAll(async () => {
    // Setup test database
    await prisma.$connect();
  });

  afterAll(async () => {
    // Cleanup
    await prisma.user.deleteMany();
    await prisma.$disconnect();
    await redis.quit();
  });

  beforeEach(async () => {
    // Clear test data
    await prisma.user.deleteMany();
  });

  describe('POST /api/auth/register', () => {
    it('should register a new user with valid data', async () => {
      const response = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'test@ucl.ac.uk',
          password: 'SecurePass123!',
          username: 'testuser',
          displayName: 'Test User',
        });

      expect(response.status).toBe(201);
      expect(response.body).toHaveProperty('user');
      expect(response.body).toHaveProperty('token');
      expect(response.body.user.email).toBe('test@ucl.ac.uk');
      expect(response.body.user).not.toHaveProperty('password');
    });

    it('should reject registration with invalid email', async () => {
      const response = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'invalid-email',
          password: 'SecurePass123!',
          username: 'testuser',
        });

      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('error');
    });

    it('should reject registration with weak password', async () => {
      const response = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'test@ucl.ac.uk',
          password: '123',
          username: 'testuser',
        });

      expect(response.status).toBe(400);
      expect(response.body.error).toContain('password');
    });

    it('should reject duplicate email registration', async () => {
      // First registration
      await request(app)
        .post('/api/auth/register')
        .send({
          email: 'test@ucl.ac.uk',
          password: 'SecurePass123!',
          username: 'testuser1',
        });

      // Duplicate registration
      const response = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'test@ucl.ac.uk',
          password: 'SecurePass123!',
          username: 'testuser2',
        });

      expect(response.status).toBe(409);
      expect(response.body.error).toContain('exists');
    });
  });

  describe('POST /api/auth/login', () => {
    beforeEach(async () => {
      // Create test user
      await request(app)
        .post('/api/auth/register')
        .send({
          email: 'login@ucl.ac.uk',
          password: 'SecurePass123!',
          username: 'loginuser',
        });
    });

    it('should login with valid credentials', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'login@ucl.ac.uk',
          password: 'SecurePass123!',
        });

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('token');
      expect(response.body).toHaveProperty('user');
    });

    it('should reject login with wrong password', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'login@ucl.ac.uk',
          password: 'WrongPassword!',
        });

      expect(response.status).toBe(401);
    });

    it('should reject login with non-existent email', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'nonexistent@ucl.ac.uk',
          password: 'SecurePass123!',
        });

      expect(response.status).toBe(401);
    });
  });

  describe('POST /api/auth/refresh', () => {
    let refreshToken: string;

    beforeEach(async () => {
      const registerResponse = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'refresh@ucl.ac.uk',
          password: 'SecurePass123!',
          username: 'refreshuser',
        });

      refreshToken = registerResponse.body.refreshToken;
    });

    it('should refresh token with valid refresh token', async () => {
      const response = await request(app)
        .post('/api/auth/refresh')
        .send({ refreshToken });

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('token');
    });

    it('should reject invalid refresh token', async () => {
      const response = await request(app)
        .post('/api/auth/refresh')
        .send({ refreshToken: 'invalid-token' });

      expect(response.status).toBe(401);
    });
  });

  describe('POST /api/auth/verify-university', () => {
    let authToken: string;

    beforeEach(async () => {
      const registerResponse = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'verify@ucl.ac.uk',
          password: 'SecurePass123!',
          username: 'verifyuser',
        });

      authToken = registerResponse.body.token;
    });

    it('should send verification email for .ac.uk domain', async () => {
      const response = await request(app)
        .post('/api/auth/verify-university')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          universityEmail: 'student@ucl.ac.uk',
        });

      expect(response.status).toBe(200);
      expect(response.body.message).toContain('verification');
    });

    it('should reject non-.ac.uk email', async () => {
      const response = await request(app)
        .post('/api/auth/verify-university')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          universityEmail: 'student@gmail.com',
        });

      expect(response.status).toBe(400);
    });
  });
});
