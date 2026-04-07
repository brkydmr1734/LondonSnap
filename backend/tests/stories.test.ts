import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../src/app';
import { prisma } from '../src/lib/prisma';
import { redis } from '../src/lib/redis';

describe('Stories API', () => {
  let authToken: string;
  let userId: string;
  let friendToken: string;
  let friendId: string;

  beforeAll(async () => {
    await prisma.$connect();

    // Create test users
    const userResponse = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'storyuser@ucl.ac.uk',
        password: 'SecurePass123!',
        username: 'storyuser',
      });

    authToken = userResponse.body.token;
    userId = userResponse.body.user.id;

    const friendResponse = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'storyfriend@ucl.ac.uk',
        password: 'SecurePass123!',
        username: 'storyfriend',
      });

    friendToken = friendResponse.body.token;
    friendId = friendResponse.body.user.id;

    // Make them friends
    const requestResponse = await request(app)
      .post('/api/friends/request')
      .set('Authorization', `Bearer ${authToken}`)
      .send({ userId: friendId });

    await request(app)
      .put(`/api/friends/request/${requestResponse.body.id}/accept`)
      .set('Authorization', `Bearer ${friendToken}`);
  });

  afterAll(async () => {
    await prisma.storyView.deleteMany();
    await prisma.story.deleteMany();
    await prisma.friendship.deleteMany();
    await prisma.friendRequest.deleteMany();
    await prisma.user.deleteMany();
    await prisma.$disconnect();
    await redis.quit();
  });

  beforeEach(async () => {
    await prisma.storyView.deleteMany();
    await prisma.story.deleteMany();
  });

  describe('POST /api/stories', () => {
    it('should create a story', async () => {
      const response = await request(app)
        .post('/api/stories')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          mediaUrl: 'https://cdn.londonsnaps.app/stories/test.jpg',
          mediaType: 'IMAGE',
          privacy: 'FRIENDS',
        });

      expect(response.status).toBe(201);
      expect(response.body).toHaveProperty('id');
      expect(response.body.userId).toBe(userId);
      expect(response.body.mediaType).toBe('IMAGE');
    });

    it('should create a story with text overlay', async () => {
      const response = await request(app)
        .post('/api/stories')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          mediaUrl: 'https://cdn.londonsnaps.app/stories/test.jpg',
          mediaType: 'IMAGE',
          textOverlay: 'Hello London!',
          textPosition: { x: 50, y: 50 },
          privacy: 'PUBLIC',
        });

      expect(response.status).toBe(201);
      expect(response.body.textOverlay).toBe('Hello London!');
    });

    it('should set correct expiration time (24h)', async () => {
      const response = await request(app)
        .post('/api/stories')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          mediaUrl: 'https://cdn.londonsnaps.app/stories/test.jpg',
          mediaType: 'IMAGE',
          privacy: 'FRIENDS',
        });

      const expiresAt = new Date(response.body.expiresAt);
      const createdAt = new Date(response.body.createdAt);
      const diffHours = (expiresAt.getTime() - createdAt.getTime()) / (1000 * 60 * 60);

      expect(diffHours).toBeCloseTo(24, 0);
    });
  });

  describe('GET /api/stories/feed', () => {
    beforeEach(async () => {
      // Friend creates stories
      await request(app)
        .post('/api/stories')
        .set('Authorization', `Bearer ${friendToken}`)
        .send({
          mediaUrl: 'https://cdn.londonsnaps.app/stories/friend1.jpg',
          mediaType: 'IMAGE',
          privacy: 'FRIENDS',
        });

      await request(app)
        .post('/api/stories')
        .set('Authorization', `Bearer ${friendToken}`)
        .send({
          mediaUrl: 'https://cdn.londonsnaps.app/stories/friend2.jpg',
          mediaType: 'IMAGE',
          privacy: 'FRIENDS',
        });
    });

    it('should return stories feed grouped by user', async () => {
      const response = await request(app)
        .get('/api/stories/feed')
        .set('Authorization', `Bearer ${authToken}`);

      expect(response.status).toBe(200);
      expect(Array.isArray(response.body)).toBe(true);
      expect(response.body.length).toBeGreaterThan(0);

      const friendStories = response.body.find((s: any) => s.userId === friendId);
      expect(friendStories).toBeDefined();
      expect(friendStories.stories.length).toBe(2);
    });

    it('should not return expired stories', async () => {
      // Create expired story directly in DB
      await prisma.story.create({
        data: {
          userId: friendId,
          mediaUrl: 'https://cdn.londonsnaps.app/stories/expired.jpg',
          mediaType: 'IMAGE',
          privacy: 'FRIENDS',
          expiresAt: new Date(Date.now() - 1000), // Already expired
        },
      });

      const response = await request(app)
        .get('/api/stories/feed')
        .set('Authorization', `Bearer ${authToken}`);

      const allStories = response.body.flatMap((s: any) => s.stories);
      expect(allStories.every((s: any) => new Date(s.expiresAt) > new Date())).toBe(true);
    });
  });

  describe('GET /api/stories/:storyId', () => {
    let storyId: string;

    beforeEach(async () => {
      const storyResponse = await request(app)
        .post('/api/stories')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          mediaUrl: 'https://cdn.londonsnaps.app/stories/test.jpg',
          mediaType: 'IMAGE',
          privacy: 'FRIENDS',
        });

      storyId = storyResponse.body.id;
    });

    it('should return story details', async () => {
      const response = await request(app)
        .get(`/api/stories/${storyId}`)
        .set('Authorization', `Bearer ${authToken}`);

      expect(response.status).toBe(200);
      expect(response.body.id).toBe(storyId);
    });

    it('should record view and return viewers for owner', async () => {
      // Friend views the story
      await request(app)
        .get(`/api/stories/${storyId}`)
        .set('Authorization', `Bearer ${friendToken}`);

      // Owner checks viewers
      const response = await request(app)
        .get(`/api/stories/${storyId}/viewers`)
        .set('Authorization', `Bearer ${authToken}`);

      expect(response.status).toBe(200);
      expect(response.body.some((v: any) => v.userId === friendId)).toBe(true);
    });
  });

  describe('DELETE /api/stories/:storyId', () => {
    let storyId: string;

    beforeEach(async () => {
      const storyResponse = await request(app)
        .post('/api/stories')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          mediaUrl: 'https://cdn.londonsnaps.app/stories/test.jpg',
          mediaType: 'IMAGE',
          privacy: 'FRIENDS',
        });

      storyId = storyResponse.body.id;
    });

    it('should delete own story', async () => {
      const response = await request(app)
        .delete(`/api/stories/${storyId}`)
        .set('Authorization', `Bearer ${authToken}`);

      expect(response.status).toBe(200);

      // Verify story is deleted
      const getResponse = await request(app)
        .get(`/api/stories/${storyId}`)
        .set('Authorization', `Bearer ${authToken}`);

      expect(getResponse.status).toBe(404);
    });

    it('should not delete other user story', async () => {
      const response = await request(app)
        .delete(`/api/stories/${storyId}`)
        .set('Authorization', `Bearer ${friendToken}`);

      expect(response.status).toBe(403);
    });
  });

  describe('POST /api/stories/:storyId/react', () => {
    let storyId: string;

    beforeEach(async () => {
      const storyResponse = await request(app)
        .post('/api/stories')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          mediaUrl: 'https://cdn.londonsnaps.app/stories/test.jpg',
          mediaType: 'IMAGE',
          privacy: 'FRIENDS',
        });

      storyId = storyResponse.body.id;
    });

    it('should add reaction to story', async () => {
      const response = await request(app)
        .post(`/api/stories/${storyId}/react`)
        .set('Authorization', `Bearer ${friendToken}`)
        .send({ emoji: '🔥' });

      expect(response.status).toBe(200);
    });
  });

  describe('POST /api/stories/:storyId/reply', () => {
    let storyId: string;

    beforeEach(async () => {
      const storyResponse = await request(app)
        .post('/api/stories')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          mediaUrl: 'https://cdn.londonsnaps.app/stories/test.jpg',
          mediaType: 'IMAGE',
          privacy: 'FRIENDS',
        });

      storyId = storyResponse.body.id;
    });

    it('should reply to story', async () => {
      const response = await request(app)
        .post(`/api/stories/${storyId}/reply`)
        .set('Authorization', `Bearer ${friendToken}`)
        .send({ message: 'Great story!' });

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('chatId');
    });
  });
});
