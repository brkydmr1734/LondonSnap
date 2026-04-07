import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../src/app';
import { prisma } from '../src/lib/prisma';
import { redis } from '../src/lib/redis';

describe('Chat API', () => {
  let authToken: string;
  let userId: string;
  let otherUserId: string;
  let otherAuthToken: string;

  beforeAll(async () => {
    await prisma.$connect();
    
    // Create test users
    const user1Response = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'chatuser1@ucl.ac.uk',
        password: 'SecurePass123!',
        username: 'chatuser1',
      });
    
    authToken = user1Response.body.token;
    userId = user1Response.body.user.id;

    const user2Response = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'chatuser2@ucl.ac.uk',
        password: 'SecurePass123!',
        username: 'chatuser2',
      });

    otherAuthToken = user2Response.body.token;
    otherUserId = user2Response.body.user.id;
  });

  afterAll(async () => {
    await prisma.message.deleteMany();
    await prisma.chatMember.deleteMany();
    await prisma.chat.deleteMany();
    await prisma.user.deleteMany();
    await prisma.$disconnect();
    await redis.quit();
  });

  describe('POST /api/chats', () => {
    it('should create a new direct chat', async () => {
      const response = await request(app)
        .post('/api/chats')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          type: 'DIRECT',
          participantIds: [otherUserId],
        });

      expect(response.status).toBe(201);
      expect(response.body).toHaveProperty('id');
      expect(response.body.type).toBe('DIRECT');
    });

    it('should create a group chat', async () => {
      const response = await request(app)
        .post('/api/chats')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          type: 'GROUP',
          name: 'Test Group',
          participantIds: [otherUserId],
        });

      expect(response.status).toBe(201);
      expect(response.body.type).toBe('GROUP');
      expect(response.body.name).toBe('Test Group');
    });

    it('should return existing direct chat instead of creating duplicate', async () => {
      // First chat
      const firstResponse = await request(app)
        .post('/api/chats')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          type: 'DIRECT',
          participantIds: [otherUserId],
        });

      // Second attempt
      const secondResponse = await request(app)
        .post('/api/chats')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          type: 'DIRECT',
          participantIds: [otherUserId],
        });

      expect(firstResponse.body.id).toBe(secondResponse.body.id);
    });
  });

  describe('GET /api/chats', () => {
    it('should return user chats', async () => {
      const response = await request(app)
        .get('/api/chats')
        .set('Authorization', `Bearer ${authToken}`);

      expect(response.status).toBe(200);
      expect(Array.isArray(response.body)).toBe(true);
    });
  });

  describe('POST /api/chats/:chatId/messages', () => {
    let chatId: string;

    beforeEach(async () => {
      const chatResponse = await request(app)
        .post('/api/chats')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          type: 'DIRECT',
          participantIds: [otherUserId],
        });

      chatId = chatResponse.body.id;
    });

    it('should send a text message', async () => {
      const response = await request(app)
        .post(`/api/chats/${chatId}/messages`)
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          type: 'TEXT',
          content: 'Hello, world!',
        });

      expect(response.status).toBe(201);
      expect(response.body.content).toBe('Hello, world!');
      expect(response.body.senderId).toBe(userId);
    });

    it('should send a media message', async () => {
      const response = await request(app)
        .post(`/api/chats/${chatId}/messages`)
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          type: 'IMAGE',
          mediaUrl: 'https://cdn.londonsnaps.app/images/test.jpg',
        });

      expect(response.status).toBe(201);
      expect(response.body.type).toBe('IMAGE');
    });

    it('should reject message from non-participant', async () => {
      // Create a new user not in the chat
      const newUserResponse = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'outsider@ucl.ac.uk',
          password: 'SecurePass123!',
          username: 'outsider',
        });

      const response = await request(app)
        .post(`/api/chats/${chatId}/messages`)
        .set('Authorization', `Bearer ${newUserResponse.body.token}`)
        .send({
          type: 'TEXT',
          content: 'Unauthorized message',
        });

      expect(response.status).toBe(403);
    });
  });

  describe('GET /api/chats/:chatId/messages', () => {
    let chatId: string;

    beforeEach(async () => {
      const chatResponse = await request(app)
        .post('/api/chats')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          type: 'DIRECT',
          participantIds: [otherUserId],
        });

      chatId = chatResponse.body.id;

      // Send some messages
      for (let i = 0; i < 5; i++) {
        await request(app)
          .post(`/api/chats/${chatId}/messages`)
          .set('Authorization', `Bearer ${authToken}`)
          .send({
            type: 'TEXT',
            content: `Message ${i}`,
          });
      }
    });

    it('should return paginated messages', async () => {
      const response = await request(app)
        .get(`/api/chats/${chatId}/messages`)
        .set('Authorization', `Bearer ${authToken}`)
        .query({ limit: 3 });

      expect(response.status).toBe(200);
      expect(response.body.messages.length).toBeLessThanOrEqual(3);
      expect(response.body).toHaveProperty('nextCursor');
    });

    it('should return messages in correct order', async () => {
      const response = await request(app)
        .get(`/api/chats/${chatId}/messages`)
        .set('Authorization', `Bearer ${authToken}`);

      const messages = response.body.messages;
      for (let i = 0; i < messages.length - 1; i++) {
        expect(new Date(messages[i].createdAt).getTime())
          .toBeGreaterThanOrEqual(new Date(messages[i + 1].createdAt).getTime());
      }
    });
  });

  describe('PUT /api/chats/:chatId/read', () => {
    let chatId: string;

    beforeEach(async () => {
      const chatResponse = await request(app)
        .post('/api/chats')
        .set('Authorization', `Bearer ${authToken}`)
        .send({
          type: 'DIRECT',
          participantIds: [otherUserId],
        });

      chatId = chatResponse.body.id;

      // Other user sends messages
      await request(app)
        .post(`/api/chats/${chatId}/messages`)
        .set('Authorization', `Bearer ${otherAuthToken}`)
        .send({
          type: 'TEXT',
          content: 'Unread message',
        });
    });

    it('should mark messages as read', async () => {
      const response = await request(app)
        .put(`/api/chats/${chatId}/read`)
        .set('Authorization', `Bearer ${authToken}`);

      expect(response.status).toBe(200);

      // Verify unread count is 0
      const chatsResponse = await request(app)
        .get('/api/chats')
        .set('Authorization', `Bearer ${authToken}`);

      const chat = chatsResponse.body.find((c: any) => c.id === chatId);
      expect(chat.unreadCount).toBe(0);
    });
  });
});
