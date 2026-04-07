import { Request, Response, NextFunction } from 'express';
import { prisma } from '../../index';
import { BadRequestError } from '../../common/utils/AppError';
import { notificationService } from '../../notifications/services/notification.service';

export class DiscoverController {
  async search(req: Request, res: Response, next: NextFunction) {
    try {
      const { q, type = 'all' } = req.query;
      if (!q || typeof q !== 'string' || q.length < 2) {
        throw new BadRequestError('Search query required (min 2 chars)');
      }

      const results: any = {};

      // Parallelize search queries when type is 'all'
      if (type === 'all') {
        const [users, events] = await Promise.all([
          prisma.user.findMany({
            where: {
              status: 'ACTIVE',
              OR: [
                { username: { contains: q, mode: 'insensitive' } },
                { displayName: { contains: q, mode: 'insensitive' } },
              ],
            },
            select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true, isVerified: true },
            take: 10,
          }),
          prisma.event.findMany({
            where: {
              status: 'ACTIVE',
              isPublic: true,
              title: { contains: q, mode: 'insensitive' },
            },
            select: { id: true, title: true, coverImageUrl: true, startTime: true, location: true },
            take: 10,
          }),
        ]);
        results.users = users;
        results.events = events;
      } else if (type === 'users') {
        results.users = await prisma.user.findMany({
          where: {
            status: 'ACTIVE',
            OR: [
              { username: { contains: q, mode: 'insensitive' } },
              { displayName: { contains: q, mode: 'insensitive' } },
            ],
          },
          select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true, isVerified: true },
          take: 10,
        });
      } else if (type === 'events') {
        results.events = await prisma.event.findMany({
          where: {
            status: 'ACTIVE',
            isPublic: true,
            title: { contains: q, mode: 'insensitive' },
          },
          select: { id: true, title: true, coverImageUrl: true, startTime: true, location: true },
          take: 10,
        });
      }

      res.json({ success: true, data: results });
    } catch (error) {
      next(error);
    }
  }

  async discoverUsers(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { limit = 20 } = req.query;

      const friendIds = await prisma.friendship.findMany({
        where: { userId: req.user.id },
        select: { friendId: true },
      });

      const users = await prisma.user.findMany({
        where: {
          id: { notIn: [req.user.id, ...friendIds.map(f => f.friendId)] },
          status: 'ACTIVE',
          privacySettings: { showInDiscover: true },
        },
        select: {
          id: true, username: true, displayName: true, avatarUrl: true,
          isVerified: true, isUniversityStudent: true,
          university: { select: { shortName: true } },
        },
        take: Number(limit),
      });

      res.json({ success: true, data: { users } });
    } catch (error) {
      next(error);
    }
  }

  async discoverStories(req: Request, res: Response, next: NextFunction) {
    try {
      const stories = await prisma.story.findMany({
        where: {
          expiresAt: { gt: new Date() },
          privacy: 'EVERYONE',
          user: { privacySettings: { showInDiscover: true } },
        },
        include: {
          user: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true, isVerified: true } },
        },
        orderBy: { viewCount: 'desc' },
        take: 20,
      });

      res.json({ success: true, data: { stories } });
    } catch (error) {
      next(error);
    }
  }

  async discoverEvents(req: Request, res: Response, next: NextFunction) {
    try {
      const events = await prisma.event.findMany({
        where: {
          status: 'ACTIVE',
          isPublic: true,
          startTime: { gte: new Date() },
        },
        include: {
          creator: { select: { id: true, displayName: true, avatarUrl: true } },
          _count: { select: { rsvps: true } },
        },
        orderBy: [{ startTime: 'asc' }],
        take: 20,
      });

      res.json({ success: true, data: { events } });
    } catch (error) {
      next(error);
    }
  }

  async studentsNearby(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const myLocation = await prisma.userLocation.findFirst({
        where: { userId: req.user.id },
        orderBy: { updatedAt: 'desc' },
      });

      if (!myLocation?.area) {
        return res.json({ success: true, data: { users: [] } });
      }

      const nearbyUsers = await prisma.user.findMany({
        where: {
          id: { not: req.user.id },
          status: 'ACTIVE',
          privacySettings: { showInNearby: true },
          locations: { some: { area: myLocation.area } },
        },
        select: {
          id: true, username: true, displayName: true, avatarUrl: true,
          avatarConfig: true, isVerified: true, isUniversityStudent: true,
        },
        take: 20,
      });

      res.json({ success: true, data: { users: nearbyUsers, area: myLocation.area } });
    } catch (error) {
      next(error);
    }
  }

  async createMatch(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { matchedUserId, type, message } = req.body;

      const match = await prisma.socialMatch.create({
        data: {
          userId: req.user.id,
          matchedUserId,
          type,
          message,
        },
      });

      await notificationService.sendPushNotification(matchedUserId, {
        type: 'MATCH_REQUEST',
        title: 'New Match Request',
        body: `Someone wants to connect with you!`,
        data: { matchId: match.id },
      });

      res.status(201).json({ success: true, data: { match } });
    } catch (error) {
      next(error);
    }
  }

  async getMatches(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const [received, sent] = await Promise.all([
        prisma.socialMatch.findMany({
          where: { matchedUserId: req.user.id },
          include: { user: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } } },
          orderBy: { createdAt: 'desc' },
        }),
        prisma.socialMatch.findMany({
          where: { userId: req.user.id },
          include: { matchedUser: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } } },
          orderBy: { createdAt: 'desc' },
        }),
      ]);

      res.json({ success: true, data: { received, sent } });
    } catch (error) {
      next(error);
    }
  }

  async respondToMatch(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { matchId } = req.params;
      const { status } = req.body;

      const match = await prisma.socialMatch.updateMany({
        where: { id: matchId, matchedUserId: req.user.id, status: 'PENDING' },
        data: { status, respondedAt: new Date() },
      });

      if (status === 'ACCEPTED') {
        const m = await prisma.socialMatch.findUnique({ where: { id: matchId } });
        if (m) {
          await notificationService.sendPushNotification(m.userId, {
            type: 'MATCH_ACCEPTED',
            title: 'Match Accepted!',
            body: 'Your match request was accepted!',
            data: { matchId },
          });
        }
      }

      res.json({ success: true, message: `Match ${status.toLowerCase()}` });
    } catch (error) {
      next(error);
    }
  }
}

export const discoverController = new DiscoverController();
