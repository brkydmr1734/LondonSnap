import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { snapService } from '../services/snap.service';
import { BadRequestError } from '../../common/utils/AppError';

const sendSnapSchema = z.object({
  recipientIds: z.array(z.string().uuid()).min(1, 'At least one recipient required'),
  mediaUrl: z.string().url(),
  mediaType: z.enum(['IMAGE', 'VIDEO']),
  thumbnailUrl: z.string().url().optional(),
  duration: z.number().positive().optional(),
  hasAudio: z.boolean().optional(),
  caption: z.string().max(200).optional(),
  drawingData: z.any().optional(),
  stickers: z.any().optional(),
  filters: z.any().optional(),
  viewDuration: z.number().min(1).max(10).optional(),
  isReplayable: z.boolean().optional(),
});

export class SnapController {
  async sendSnap(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const data = sendSnapSchema.parse(req.body);
      const { recipientIds, ...snapData } = data;

      const snap = await snapService.sendSnap(req.user.id, recipientIds, snapData);

      res.status(201).json({
        success: true,
        message: 'Snap sent',
        data: { snap },
      });
    } catch (error) {
      next(error);
    }
  }

  async getReceivedSnaps(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const snaps = await snapService.getReceivedSnaps(req.user.id);

      res.json({
        success: true,
        data: { snaps },
      });
    } catch (error) {
      next(error);
    }
  }

  async getSentSnaps(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const snaps = await snapService.getSentSnaps(req.user.id);

      res.json({
        success: true,
        data: { snaps },
      });
    } catch (error) {
      next(error);
    }
  }

  async openSnap(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { snapId } = req.params;
      const result = await snapService.openSnap(req.user.id, snapId);

      res.json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  async reportScreenshot(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { snapId } = req.params;
      await snapService.reportScreenshot(req.user.id, snapId);

      res.json({
        success: true,
        message: 'Screenshot reported',
      });
    } catch (error) {
      next(error);
    }
  }

  async getSnapStatus(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { snapId } = req.params;
      const snap = await snapService.getSnapStatus(req.user.id, snapId);

      res.json({
        success: true,
        data: { snap },
      });
    } catch (error) {
      next(error);
    }
  }

  async getStreaks(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const streaks = await snapService.getStreaks(req.user.id);

      res.json({
        success: true,
        data: { streaks },
      });
    } catch (error) {
      next(error);
    }
  }

  // Save a snap (toggle)
  async saveSnap(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { snapId } = req.params;
      const result = await snapService.saveSnap(req.user.id, snapId);

      res.json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  // Unsave a snap
  async unsaveSnap(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { snapId } = req.params;
      const result = await snapService.unsaveSnap(req.user.id, snapId);

      res.json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  // Get saved snaps
  async getSavedSnaps(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const limit = parseInt(req.query.limit as string) || 20;
      const offset = parseInt(req.query.offset as string) || 0;

      const result = await snapService.getSavedSnaps(req.user.id, limit, offset);

      res.json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  // Check if snap is saved
  async isSnapSaved(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { snapId } = req.params;
      const result = await snapService.isSnapSaved(req.user.id, snapId);

      res.json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }
}

export const snapController = new SnapController();
