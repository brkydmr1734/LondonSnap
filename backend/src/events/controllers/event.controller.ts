import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../../index';
import { BadRequestError, NotFoundError, ForbiddenError } from '../../common/utils/AppError';
import { notificationService } from '../../notifications/services/notification.service';

const createEventSchema = z.object({
  title: z.string().min(1).max(100),
  description: z.string().max(1000),
  coverImageUrl: z.string().url().optional(),
  location: z.string().max(200),
  latitude: z.number().optional(),
  longitude: z.number().optional(),
  area: z.enum(['SOHO', 'CAMDEN', 'SHOREDITCH', 'BRIXTON', 'HACKNEY', 'KENSINGTON', 'WESTMINSTER', 'ISLINGTON', 'GREENWICH', 'STRATFORD', 'KINGS_CROSS', 'NOTTING_HILL', 'FULHAM', 'WIMBLEDON', 'OTHER']).optional(),
  startTime: z.string().datetime(),
  endTime: z.string().datetime().optional(),
  isOnline: z.boolean().optional(),
  onlineLink: z.string().url().optional(),
  maxAttendees: z.number().positive().optional(),
  isPublic: z.boolean().optional(),
});

export class EventController {
  async getEvents(req: Request, res: Response, next: NextFunction) {
    try {
      const { limit = 20, offset = 0, upcoming = true } = req.query;

      const events = await prisma.event.findMany({
        where: {
          status: 'ACTIVE',
          isPublic: true,
          ...(upcoming === 'true' && { startTime: { gte: new Date() } }),
        },
        include: {
          creator: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
          university: { select: { id: true, name: true, shortName: true } },
          _count: { select: { rsvps: true } },
        },
        orderBy: { startTime: 'asc' },
        take: Number(limit),
        skip: Number(offset),
      });

      res.json({ success: true, data: { events } });
    } catch (error) {
      next(error);
    }
  }

  async getEventById(req: Request, res: Response, next: NextFunction) {
    try {
      const { eventId } = req.params;

      const event = await prisma.event.findUnique({
        where: { id: eventId },
        include: {
          creator: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
          university: { select: { id: true, name: true, shortName: true } },
          rsvps: {
            take: 10,
            include: {
              user: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
            },
          },
          _count: { select: { rsvps: true } },
        },
      });

      if (!event) throw new NotFoundError('Event not found');

      // Check if user has RSVP'd
      let userRsvp = null;
      if (req.user) {
        userRsvp = await prisma.eventRSVP.findUnique({
          where: { eventId_userId: { eventId, userId: req.user.id } },
        });
      }

      res.json({ success: true, data: { event, userRsvp } });
    } catch (error) {
      next(error);
    }
  }

  async createEvent(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const data = createEventSchema.parse(req.body);

      const event = await prisma.event.create({
        data: {
          ...data,
          startTime: new Date(data.startTime),
          endTime: data.endTime ? new Date(data.endTime) : null,
          creatorId: req.user.id,
          universityId: req.user.universityId,
        },
        include: {
          creator: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        },
      });

      res.status(201).json({ success: true, data: { event } });
    } catch (error) {
      next(error);
    }
  }

  async updateEvent(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { eventId } = req.params;

      const existing = await prisma.event.findUnique({ where: { id: eventId } });
      if (!existing) throw new NotFoundError('Event not found');
      if (existing.creatorId !== req.user.id) throw new ForbiddenError('Not authorized');

      const event = await prisma.event.update({
        where: { id: eventId },
        data: {
          ...req.body,
          startTime: req.body.startTime ? new Date(req.body.startTime) : undefined,
          endTime: req.body.endTime ? new Date(req.body.endTime) : undefined,
        },
      });

      res.json({ success: true, data: { event } });
    } catch (error) {
      next(error);
    }
  }

  async deleteEvent(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { eventId } = req.params;

      const existing = await prisma.event.findUnique({ where: { id: eventId } });
      if (!existing) throw new NotFoundError('Event not found');
      if (existing.creatorId !== req.user.id) throw new ForbiddenError('Not authorized');

      await prisma.event.update({
        where: { id: eventId },
        data: { status: 'CANCELLED' },
      });

      res.json({ success: true, message: 'Event deleted' });
    } catch (error) {
      next(error);
    }
  }

  async rsvpEvent(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { eventId } = req.params;
      const { status = 'GOING' } = req.body;

      const event = await prisma.event.findUnique({ where: { id: eventId } });
      if (!event || event.status !== 'ACTIVE') throw new NotFoundError('Event not found');

      if (event.maxAttendees) {
        const count = await prisma.eventRSVP.count({
          where: { eventId, status: 'GOING' },
        });
        if (count >= event.maxAttendees) throw new BadRequestError('Event is full');
      }

      const rsvp = await prisma.eventRSVP.upsert({
        where: { eventId_userId: { eventId, userId: req.user.id } },
        update: { status },
        create: { eventId, userId: req.user.id, status },
      });

      res.json({ success: true, data: { rsvp } });
    } catch (error) {
      next(error);
    }
  }

  async cancelRsvp(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { eventId } = req.params;

      await prisma.eventRSVP.delete({
        where: { eventId_userId: { eventId, userId: req.user.id } },
      });

      res.json({ success: true, message: 'RSVP cancelled' });
    } catch (error) {
      next(error);
    }
  }

  async getAttendees(req: Request, res: Response, next: NextFunction) {
    try {
      const { eventId } = req.params;

      const attendees = await prisma.eventRSVP.findMany({
        where: { eventId },
        include: {
          user: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true, isVerified: true } },
        },
        orderBy: { createdAt: 'asc' },
      });

      res.json({ success: true, data: { attendees } });
    } catch (error) {
      next(error);
    }
  }

  async getUniversityEvents(req: Request, res: Response, next: NextFunction) {
    try {
      const { universityId } = req.params;

      const events = await prisma.event.findMany({
        where: {
          universityId,
          status: 'ACTIVE',
          startTime: { gte: new Date() },
        },
        include: {
          creator: { select: { id: true, displayName: true, avatarUrl: true } },
          _count: { select: { rsvps: true } },
        },
        orderBy: { startTime: 'asc' },
      });

      res.json({ success: true, data: { events } });
    } catch (error) {
      next(error);
    }
  }

  async getEventsByArea(req: Request, res: Response, next: NextFunction) {
    try {
      const { area } = req.params;

      const events = await prisma.event.findMany({
        where: {
          area: area as any,
          status: 'ACTIVE',
          isPublic: true,
          startTime: { gte: new Date() },
        },
        include: {
          creator: { select: { id: true, displayName: true, avatarUrl: true } },
          _count: { select: { rsvps: true } },
        },
        orderBy: { startTime: 'asc' },
      });

      res.json({ success: true, data: { events } });
    } catch (error) {
      next(error);
    }
  }
}

export const eventController = new EventController();
