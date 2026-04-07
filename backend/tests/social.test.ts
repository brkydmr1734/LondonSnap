import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../src/app';
import { prisma } from '../src/lib/prisma';
import { redis } from '../src/lib/redis';

describe('Social API', () => {
  let user1Token: string;
  let user1Id: string;
  let user2Token: string;
  let user2Id: string;
  let user3Token: string;
  let user3Id: string;

  beforeAll(async () => {
    await prisma.$connect();

    // Create test users
    const user1Response = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'social1@ucl.ac.uk',
        password: 'SecurePass123!',
        username: 'socialuser1',
        displayName: 'Social User 1',
      });

    user1Token = user1Response.body.token;
    user1Id = user1Response.body.user.id;

    const user2Response = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'social2@ucl.ac.uk',
        password: 'SecurePass123!',
        username: 'socialuser2',
        displayName: 'Social User 2',
      });

    user2Token = user2Response.body.token;
    user2Id = user2Response.body.user.id;

    const user3Response = await request(app)
      .post('/api/auth/register')
      .send({
        email: 'social3@ucl.ac.uk',
        password: 'SecurePass123!',
        username: 'socialuser3',
        displayName: 'Social User 3',
      });

    user3Token = user3Response.body.token;
    user3Id = user3Response.body.user.id;
  });

  afterAll(async () => {
    await prisma.streak.deleteMany();
    await prisma.friendship.deleteMany();
    await prisma.friendRequest.deleteMany();
    await prisma.user.deleteMany();
    await prisma.$disconnect();
    await redis.quit();
  });

  describe('Friend Requests', () => {
    beforeEach(async () => {
      await prisma.friendRequest.deleteMany();
      await prisma.friendship.deleteMany();
    });

    describe('POST /api/friends/request', () => {
      it('should send a friend request', async () => {
        const response = await request(app)
          .post('/api/friends/request')
          .set('Authorization', `Bearer ${user1Token}`)
          .send({ userId: user2Id });

        expect(response.status).toBe(201);
        expect(response.body.senderId).toBe(user1Id);
        expect(response.body.receiverId).toBe(user2Id);
        expect(response.body.status).toBe('PENDING');
      });

      it('should not send duplicate request', async () => {
        await request(app)
          .post('/api/friends/request')
          .set('Authorization', `Bearer ${user1Token}`)
          .send({ userId: user2Id });

        const response = await request(app)
          .post('/api/friends/request')
          .set('Authorization', `Bearer ${user1Token}`)
          .send({ userId: user2Id });

        expect(response.status).toBe(409);
      });

      it('should not send request to self', async () => {
        const response = await request(app)
          .post('/api/friends/request')
          .set('Authorization', `Bearer ${user1Token}`)
          .send({ userId: user1Id });

        expect(response.status).toBe(400);
      });
    });

    describe('PUT /api/friends/request/:requestId/accept', () => {
      let requestId: string;

      beforeEach(async () => {
        const requestResponse = await request(app)
          .post('/api/friends/request')
          .set('Authorization', `Bearer ${user1Token}`)
          .send({ userId: user2Id });

        requestId = requestResponse.body.id;
      });

      it('should accept friend request', async () => {
        const response = await request(app)
          .put(`/api/friends/request/${requestId}/accept`)
          .set('Authorization', `Bearer ${user2Token}`);

        expect(response.status).toBe(200);
        expect(response.body.status).toBe('ACCEPTED');
      });

      it('should not allow sender to accept', async () => {
        const response = await request(app)
          .put(`/api/friends/request/${requestId}/accept`)
          .set('Authorization', `Bearer ${user1Token}`);

        expect(response.status).toBe(403);
      });
    });

    describe('PUT /api/friends/request/:requestId/decline', () => {
      let requestId: string;

      beforeEach(async () => {
        const requestResponse = await request(app)
          .post('/api/friends/request')
          .set('Authorization', `Bearer ${user1Token}`)
          .send({ userId: user2Id });

        requestId = requestResponse.body.id;
      });

      it('should decline friend request', async () => {
        const response = await request(app)
          .put(`/api/friends/request/${requestId}/decline`)
          .set('Authorization', `Bearer ${user2Token}`);

        expect(response.status).toBe(200);
        expect(response.body.status).toBe('DECLINED');
      });
    });
  });

  describe('Friendships', () => {
    beforeEach(async () => {
      await prisma.friendship.deleteMany();
      await prisma.friendRequest.deleteMany();

      // Create friendship between user1 and user2
      const requestResponse = await request(app)
        .post('/api/friends/request')
        .set('Authorization', `Bearer ${user1Token}`)
        .send({ userId: user2Id });

      await request(app)
        .put(`/api/friends/request/${requestResponse.body.id}/accept`)
        .set('Authorization', `Bearer ${user2Token}`);
    });

    describe('GET /api/friends', () => {
      it('should return friends list', async () => {
        const response = await request(app)
          .get('/api/friends')
          .set('Authorization', `Bearer ${user1Token}`);

        expect(response.status).toBe(200);
        expect(Array.isArray(response.body)).toBe(true);
        expect(response.body.length).toBe(1);
        expect(response.body[0].id).toBe(user2Id);
      });
    });

    describe('GET /api/friends/mutual/:userId', () => {
      beforeEach(async () => {
        // Create friendship between user2 and user3
        const requestResponse = await request(app)
          .post('/api/friends/request')
          .set('Authorization', `Bearer ${user2Token}`)
          .send({ userId: user3Id });

        await request(app)
          .put(`/api/friends/request/${requestResponse.body.id}/accept`)
          .set('Authorization', `Bearer ${user3Token}`);
      });

      it('should return mutual friends', async () => {
        const response = await request(app)
          .get(`/api/friends/mutual/${user3Id}`)
          .set('Authorization', `Bearer ${user1Token}`);

        expect(response.status).toBe(200);
        expect(Array.isArray(response.body)).toBe(true);
        expect(response.body.some((f: any) => f.id === user2Id)).toBe(true);
      });
    });

    describe('DELETE /api/friends/:userId', () => {
      it('should remove friendship', async () => {
        const response = await request(app)
          .delete(`/api/friends/${user2Id}`)
          .set('Authorization', `Bearer ${user1Token}`);

        expect(response.status).toBe(200);

        // Verify friendship is removed
        const friendsResponse = await request(app)
          .get('/api/friends')
          .set('Authorization', `Bearer ${user1Token}`);

        expect(friendsResponse.body.length).toBe(0);
      });
    });
  });

  describe('Streaks', () => {
    beforeEach(async () => {
      await prisma.streak.deleteMany();
      await prisma.friendship.deleteMany();
      await prisma.friendRequest.deleteMany();

      // Create friendship
      const requestResponse = await request(app)
        .post('/api/friends/request')
        .set('Authorization', `Bearer ${user1Token}`)
        .send({ userId: user2Id });

      await request(app)
        .put(`/api/friends/request/${requestResponse.body.id}/accept`)
        .set('Authorization', `Bearer ${user2Token}`);
    });

    describe('GET /api/friends/:userId/streak', () => {
      it('should return streak info', async () => {
        const response = await request(app)
          .get(`/api/friends/${user2Id}/streak`)
          .set('Authorization', `Bearer ${user1Token}`);

        expect(response.status).toBe(200);
        expect(response.body).toHaveProperty('count');
        expect(response.body).toHaveProperty('lastActivity');
      });
    });

    describe('POST /api/friends/:userId/streak/update', () => {
      it('should update streak', async () => {
        const response = await request(app)
          .post(`/api/friends/${user2Id}/streak/update`)
          .set('Authorization', `Bearer ${user1Token}`);

        expect(response.status).toBe(200);
        expect(response.body.count).toBeGreaterThanOrEqual(1);
      });
    });
  });

  describe('Blocking', () => {
    beforeEach(async () => {
      await prisma.block.deleteMany();
    });

    describe('POST /api/users/:userId/block', () => {
      it('should block a user', async () => {
        const response = await request(app)
          .post(`/api/users/${user2Id}/block`)
          .set('Authorization', `Bearer ${user1Token}`);

        expect(response.status).toBe(200);
      });

      it('should prevent blocked user from sending requests', async () => {
        await request(app)
          .post(`/api/users/${user2Id}/block`)
          .set('Authorization', `Bearer ${user1Token}`);

        const response = await request(app)
          .post('/api/friends/request')
          .set('Authorization', `Bearer ${user2Token}`)
          .send({ userId: user1Id });

        expect(response.status).toBe(403);
      });
    });

    describe('DELETE /api/users/:userId/block', () => {
      beforeEach(async () => {
        await request(app)
          .post(`/api/users/${user2Id}/block`)
          .set('Authorization', `Bearer ${user1Token}`);
      });

      it('should unblock a user', async () => {
        const response = await request(app)
          .delete(`/api/users/${user2Id}/block`)
          .set('Authorization', `Bearer ${user1Token}`);

        expect(response.status).toBe(200);
      });
    });

    describe('GET /api/users/blocked', () => {
      beforeEach(async () => {
        await request(app)
          .post(`/api/users/${user2Id}/block`)
          .set('Authorization', `Bearer ${user1Token}`);
      });

      it('should return blocked users', async () => {
        const response = await request(app)
          .get('/api/users/blocked')
          .set('Authorization', `Bearer ${user1Token}`);

        expect(response.status).toBe(200);
        expect(Array.isArray(response.body)).toBe(true);
        expect(response.body.some((u: any) => u.id === user2Id)).toBe(true);
      });
    });
  });
});
