import { Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import dayjs from 'dayjs';
import { prisma } from '../../index';
import { BadRequestError, UnauthorizedError, NotFoundError } from '../../common/utils/AppError';

const JWT_SECRET = process.env.JWT_SECRET!;
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '24h';
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || JWT_SECRET;
const JWT_REFRESH_EXPIRES_IN = process.env.JWT_REFRESH_EXPIRES_IN || '7d';

export class AdminController {

  // ==================== AUTH ====================

  async login(req: Request, res: Response, next: NextFunction) {
    try {
      const { email, password } = req.body;
      if (!email || !password) throw new BadRequestError('Email and password required');

      const user = await prisma.user.findUnique({
        where: { email: email.toLowerCase() },
        select: {
          id: true, email: true, username: true, displayName: true,
          avatarUrl: true, passwordHash: true, isAdmin: true, status: true,
        },
      });

      if (!user || !user.passwordHash) {
        throw new UnauthorizedError('Invalid credentials');
      }

      if (!user.isAdmin) {
        throw new UnauthorizedError('Admin access required');
      }

      if (user.status !== 'ACTIVE') {
        throw new UnauthorizedError('Account is not active');
      }

      const isValid = await bcrypt.compare(password, user.passwordHash);
      if (!isValid) {
        throw new UnauthorizedError('Invalid credentials');
      }

      // Generate tokens
      const accessToken = jwt.sign(
        { userId: user.id, type: 'access' },
        JWT_SECRET,
        { expiresIn: '24h' } as any
      );
      const refreshToken = jwt.sign(
        { userId: user.id, type: 'refresh' },
        JWT_REFRESH_SECRET,
        { expiresIn: '7d' } as any
      );

      // Create session
      await prisma.session.create({
        data: {
          userId: user.id,
          token: accessToken,
          refreshToken,
          deviceType: 'WEB',
          deviceName: 'Admin Panel',
          ipAddress: req.ip,
          userAgent: req.headers['user-agent'],
          expiresAt: dayjs().add(7, 'day').toDate(),
        },
      });

      res.json({
        success: true,
        data: {
          user: {
            id: user.id,
            email: user.email,
            name: user.displayName,
            role: 'ADMIN',
          },
          token: accessToken,
        },
      });
    } catch (error) {
      next(error);
    }
  }

  // ==================== DASHBOARD ====================

  async getDashboardStats(req: Request, res: Response, next: NextFunction) {
    try {
      const now = new Date();
      const weekAgo = dayjs().subtract(7, 'day').toDate();
      const dayAgo = dayjs().subtract(24, 'hour').toDate();
      const todayStart = dayjs().startOf('day').toDate();
      const weekStart = dayjs().startOf('week').toDate();

      const [
        totalUsers, activeUsers, newUsers,
        totalChats, activeChats,
        storiesToday, snapsToday,
        pendingReports, activeStreaks, eventsThisWeek,
      ] = await Promise.all([
        prisma.user.count({ where: { status: 'ACTIVE' } }),
        prisma.user.count({ where: { lastSeenAt: { gte: weekAgo } } }),
        prisma.user.count({ where: { createdAt: { gte: weekAgo } } }),
        prisma.chat.count(),
        prisma.chat.count({ where: { lastMessageAt: { gte: dayAgo } } }),
        prisma.story.count({ where: { createdAt: { gte: todayStart } } }),
        prisma.snap.count({ where: { createdAt: { gte: todayStart } } }),
        prisma.report.count({ where: { status: 'PENDING' } }),
        prisma.streak.count({ where: { isActive: true } }),
        prisma.event.count({ where: { startTime: { gte: weekStart }, status: 'ACTIVE' } }),
      ]);

      res.json({
        success: true,
        data: {
          stats: {
            totalUsers, activeUsers, newUsers,
            totalChats, activeChats,
            storiesToday, snapsToday,
            pendingReports, activeStreaks, eventsThisWeek,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  }

  async getDashboardActivity(req: Request, res: Response, next: NextFunction) {
    try {
      const [recentUsers, recentReports, recentEvents] = await Promise.all([
        prisma.user.findMany({
          select: { id: true, displayName: true, username: true, createdAt: true },
          orderBy: { createdAt: 'desc' },
          take: 10,
        }),
        prisma.report.findMany({
          select: {
            id: true, reason: true, status: true, createdAt: true,
            author: { select: { displayName: true } },
          },
          orderBy: { createdAt: 'desc' },
          take: 10,
        }),
        prisma.event.findMany({
          select: { id: true, title: true, status: true, createdAt: true },
          orderBy: { createdAt: 'desc' },
          take: 5,
        }),
      ]);

      // Merge and sort by time
      const activity = [
        ...recentUsers.map(u => ({
          id: u.id, type: 'USER_JOINED' as const,
          description: `${u.displayName} (@${u.username}) joined`,
          createdAt: u.createdAt,
        })),
        ...recentReports.map(r => ({
          id: r.id, type: 'REPORT' as const,
          description: `New ${r.reason.toLowerCase()} report by ${r.author.displayName}`,
          createdAt: r.createdAt,
        })),
        ...recentEvents.map(e => ({
          id: e.id, type: 'EVENT' as const,
          description: `Event "${e.title}" created`,
          createdAt: e.createdAt,
        })),
      ].sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
       .slice(0, 20);

      res.json({ success: true, data: { activity } });
    } catch (error) {
      next(error);
    }
  }

  // ==================== USERS ====================

  async getUsers(req: Request, res: Response, next: NextFunction) {
    try {
      const { q, status, universityId, page = '1', limit = '20' } = req.query;
      const skip = (Number(page) - 1) * Number(limit);

      const where: any = {};
      if (q && typeof q === 'string') {
        where.OR = [
          { username: { contains: q, mode: 'insensitive' } },
          { displayName: { contains: q, mode: 'insensitive' } },
          { email: { contains: q, mode: 'insensitive' } },
        ];
      }
      if (status) where.status = status;
      if (universityId) where.universityId = universityId;

      const [users, total] = await Promise.all([
        prisma.user.findMany({
          where,
          select: {
            id: true, email: true, username: true, displayName: true,
            avatarUrl: true, isVerified: true, isUniversityStudent: true,
            status: true, createdAt: true, lastSeenAt: true, isAdmin: true,
            university: { select: { id: true, shortName: true, name: true } },
          },
          orderBy: { createdAt: 'desc' },
          take: Number(limit),
          skip,
        }),
        prisma.user.count({ where }),
      ]);

      res.json({
        success: true,
        data: { users, total, page: Number(page), totalPages: Math.ceil(total / Number(limit)) },
      });
    } catch (error) {
      next(error);
    }
  }

  async getUserDetail(req: Request, res: Response, next: NextFunction) {
    try {
      const { userId } = req.params;

      const [user, friendCount, snapCount, storyCount, reportCount] = await Promise.all([
        prisma.user.findUnique({
          where: { id: userId },
          select: {
            id: true, email: true, phone: true, username: true, displayName: true,
            avatarUrl: true, bio: true, birthday: true, gender: true,
            isVerified: true, isUniversityStudent: true, isAdmin: true,
            status: true, suspensionReason: true, suspendedUntil: true,
            createdAt: true, lastSeenAt: true, isOnline: true,
            university: { select: { id: true, name: true, shortName: true } },
          },
        }),
        prisma.friendship.count({ where: { userId } }),
        prisma.snap.count({ where: { senderId: userId } }),
        prisma.story.count({ where: { userId } }),
        prisma.report.count({ where: { reportedUserId: userId } }),
      ]);

      if (!user) throw new NotFoundError('User not found');

      res.json({
        success: true,
        data: { user, stats: { friendCount, snapCount, storyCount, reportCount } },
      });
    } catch (error) {
      next(error);
    }
  }

  async suspendUser(req: Request, res: Response, next: NextFunction) {
    try {
      const { userId } = req.params;
      const { reason, days = 7 } = req.body;

      await prisma.user.update({
        where: { id: userId },
        data: {
          status: 'SUSPENDED',
          suspensionReason: reason,
          suspendedUntil: dayjs().add(Number(days), 'day').toDate(),
        },
      });
      await prisma.session.deleteMany({ where: { userId } });

      res.json({ success: true, message: 'User suspended' });
    } catch (error) {
      next(error);
    }
  }

  async unsuspendUser(req: Request, res: Response, next: NextFunction) {
    try {
      const { userId } = req.params;
      await prisma.user.update({
        where: { id: userId },
        data: { status: 'ACTIVE', suspensionReason: null, suspendedUntil: null },
      });
      res.json({ success: true, message: 'User unsuspended' });
    } catch (error) {
      next(error);
    }
  }

  async banUser(req: Request, res: Response, next: NextFunction) {
    try {
      const { userId } = req.params;
      const { reason } = req.body;

      await prisma.user.update({
        where: { id: userId },
        data: { status: 'DELETED', suspensionReason: reason, deletedAt: new Date() },
      });
      await prisma.session.deleteMany({ where: { userId } });

      res.json({ success: true, message: 'User banned' });
    } catch (error) {
      next(error);
    }
  }

  // ==================== REPORTS ====================

  async getReports(req: Request, res: Response, next: NextFunction) {
    try {
      const { status, type, page = '1', limit = '50' } = req.query;
      const skip = (Number(page) - 1) * Number(limit);

      const where: any = {};
      if (status && status !== 'ALL') where.status = status;
      if (type && type !== 'ALL') {
        // Map type to reportedXId presence
        const typeMap: Record<string, string> = {
          USER: 'reportedUserId', SNAP: 'reportedSnapId',
          STORY: 'reportedStoryId', MESSAGE: 'reportedMessageId', EVENT: 'reportedEventId',
        };
        if (typeMap[type as string]) where[typeMap[type as string]] = { not: null };
      }

      const [reports, total] = await Promise.all([
        prisma.report.findMany({
          where,
          include: {
            author: { select: { id: true, username: true, displayName: true } },
            reportedUser: { select: { id: true, username: true, displayName: true } },
          },
          orderBy: { createdAt: 'desc' },
          take: Number(limit),
          skip,
        }),
        prisma.report.count({ where }),
      ]);

      res.json({
        success: true,
        data: { reports, total, page: Number(page), totalPages: Math.ceil(total / Number(limit)) },
      });
    } catch (error) {
      next(error);
    }
  }

  async resolveReport(req: Request, res: Response, next: NextFunction) {
    try {
      const { reportId } = req.params;
      const { resolution, reviewNotes } = req.body;

      await prisma.report.update({
        where: { id: reportId },
        data: {
          status: 'RESOLVED',
          resolution: resolution || 'NO_ACTION',
          reviewNotes,
          reviewedBy: req.user?.id,
          reviewedAt: new Date(),
        },
      });

      res.json({ success: true, message: 'Report resolved' });
    } catch (error) {
      next(error);
    }
  }

  async dismissReport(req: Request, res: Response, next: NextFunction) {
    try {
      const { reportId } = req.params;

      await prisma.report.update({
        where: { id: reportId },
        data: {
          status: 'DISMISSED',
          resolution: 'NO_ACTION',
          reviewedBy: req.user?.id,
          reviewedAt: new Date(),
        },
      });

      res.json({ success: true, message: 'Report dismissed' });
    } catch (error) {
      next(error);
    }
  }

  // ==================== EVENTS ====================

  async getEvents(req: Request, res: Response, next: NextFunction) {
    try {
      const { q, status, page = '1', limit = '20' } = req.query;
      const skip = (Number(page) - 1) * Number(limit);

      const where: any = {};
      if (q && typeof q === 'string') {
        where.title = { contains: q, mode: 'insensitive' };
      }
      if (status && status !== 'ALL') where.status = status;

      const [events, total] = await Promise.all([
        prisma.event.findMany({
          where,
          include: {
            creator: { select: { id: true, displayName: true, avatarUrl: true } },
            university: { select: { id: true, shortName: true } },
            _count: { select: { rsvps: true } },
          },
          orderBy: { createdAt: 'desc' },
          take: Number(limit),
          skip,
        }),
        prisma.event.count({ where }),
      ]);

      res.json({
        success: true,
        data: { events, total, page: Number(page), totalPages: Math.ceil(total / Number(limit)) },
      });
    } catch (error) {
      next(error);
    }
  }

  async updateEventStatus(req: Request, res: Response, next: NextFunction) {
    try {
      const { eventId } = req.params;
      const { status } = req.body;

      if (!['DRAFT', 'ACTIVE', 'CANCELLED', 'COMPLETED'].includes(status)) {
        throw new BadRequestError('Invalid status');
      }

      await prisma.event.update({
        where: { id: eventId },
        data: { status },
      });

      res.json({ success: true, message: `Event status updated to ${status}` });
    } catch (error) {
      next(error);
    }
  }

  async deleteEvent(req: Request, res: Response, next: NextFunction) {
    try {
      const { eventId } = req.params;
      await prisma.event.delete({ where: { id: eventId } });
      res.json({ success: true, message: 'Event deleted' });
    } catch (error) {
      next(error);
    }
  }

  // ==================== UNIVERSITIES ====================

  async getUniversities(req: Request, res: Response, next: NextFunction) {
    try {
      const { q, status } = req.query;
      const where: any = {};
      if (q && typeof q === 'string') {
        where.OR = [
          { name: { contains: q, mode: 'insensitive' } },
          { shortName: { contains: q, mode: 'insensitive' } },
        ];
      }
      if (status && status !== 'ALL') where.isVerified = status === 'ACTIVE';

      const universities = await prisma.university.findMany({
        where,
        include: {
          _count: { select: { users: true, circles: true, events: true } },
        },
        orderBy: { name: 'asc' },
      });

      res.json({ success: true, data: { universities } });
    } catch (error) {
      next(error);
    }
  }

  async createUniversity(req: Request, res: Response, next: NextFunction) {
    try {
      const { name, shortName, domain, location, logoUrl } = req.body;
      if (!name || !shortName || !domain) {
        throw new BadRequestError('Name, shortName, and domain are required');
      }

      const university = await prisma.university.create({
        data: { name, shortName, domain, location, logoUrl },
      });

      res.status(201).json({ success: true, data: { university } });
    } catch (error) {
      next(error);
    }
  }

  async updateUniversity(req: Request, res: Response, next: NextFunction) {
    try {
      const { universityId } = req.params;
      const { name, shortName, domain, location, logoUrl, isVerified } = req.body;

      const university = await prisma.university.update({
        where: { id: universityId },
        data: {
          ...(name && { name }),
          ...(shortName && { shortName }),
          ...(domain && { domain }),
          ...(location !== undefined && { location }),
          ...(logoUrl !== undefined && { logoUrl }),
          ...(isVerified !== undefined && { isVerified }),
        },
      });

      res.json({ success: true, data: { university } });
    } catch (error) {
      next(error);
    }
  }

  async deleteUniversity(req: Request, res: Response, next: NextFunction) {
    try {
      const { universityId } = req.params;
      await prisma.university.delete({ where: { id: universityId } });
      res.json({ success: true, message: 'University deleted' });
    } catch (error) {
      next(error);
    }
  }
}

export const adminController = new AdminController();
