import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../../index';
import { BadRequestError, NotFoundError, ForbiddenError } from '../../common/utils/AppError';
import dayjs from 'dayjs';

const createReportSchema = z.object({
  reportedUserId: z.string().uuid().optional(),
  reportedSnapId: z.string().uuid().optional(),
  reportedStoryId: z.string().uuid().optional(),
  reportedMessageId: z.string().uuid().optional(),
  reportedEventId: z.string().uuid().optional(),
  reason: z.enum(['SPAM', 'HARASSMENT', 'INAPPROPRIATE_CONTENT', 'IMPERSONATION', 'VIOLENCE', 'HATE_SPEECH', 'SELF_HARM', 'OTHER']),
  description: z.string().max(500).optional(),
});

export class ModerationController {
  async createReport(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const data = createReportSchema.parse(req.body);

      const report = await prisma.report.create({
        data: {
          authorId: req.user.id,
          ...data,
        },
      });

      res.status(201).json({ success: true, data: { report } });
    } catch (error) {
      next(error);
    }
  }

  async getReports(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const reports = await prisma.report.findMany({
        where: { authorId: req.user.id },
        orderBy: { createdAt: 'desc' },
      });

      res.json({ success: true, data: { reports } });
    } catch (error) {
      next(error);
    }
  }

  async getReportById(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { reportId } = req.params;

      const report = await prisma.report.findFirst({
        where: { id: reportId, authorId: req.user.id },
      });

      if (!report) throw new NotFoundError('Report not found');
      res.json({ success: true, data: { report } });
    } catch (error) {
      next(error);
    }
  }

  async updateReport(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { reportId } = req.params;
      const { description } = req.body;

      const report = await prisma.report.updateMany({
        where: { id: reportId, authorId: req.user.id, status: 'PENDING' },
        data: { description },
      });

      res.json({ success: true, message: 'Report updated' });
    } catch (error) {
      next(error);
    }
  }

  // Admin functions
  async getAllReports(req: Request, res: Response, next: NextFunction) {
    try {
      const { status, limit = 50, offset = 0 } = req.query;

      const reports = await prisma.report.findMany({
        where: status ? { status: status as any } : undefined,
        include: {
          author: { select: { id: true, username: true, displayName: true } },
          reportedUser: { select: { id: true, username: true, displayName: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: Number(limit),
        skip: Number(offset),
      });

      res.json({ success: true, data: { reports } });
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

      // Terminate all sessions
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
        data: {
          status: 'ACTIVE',
          suspensionReason: null,
          suspendedUntil: null,
        },
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
        data: {
          status: 'DELETED',
          suspensionReason: reason,
          deletedAt: new Date(),
        },
      });

      // Terminate all sessions
      await prisma.session.deleteMany({ where: { userId } });

      res.json({ success: true, message: 'User banned' });
    } catch (error) {
      next(error);
    }
  }
}

export const moderationController = new ModerationController();
