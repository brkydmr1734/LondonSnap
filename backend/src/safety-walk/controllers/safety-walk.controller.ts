import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { safetyWalkService } from '../services/safety-walk.service';
import { BadRequestError } from '../../common/utils/AppError';

// Validation schemas
const findCompanionsSchema = z.object({
  startLat: z.number().min(-90).max(90),
  startLng: z.number().min(-180).max(180),
  endLat: z.number().min(-90).max(90),
  endLng: z.number().min(-180).max(180),
  radius: z.number().min(100).max(10000).optional(),
});

const createWalkRequestSchema = z.object({
  companionId: z.string().uuid(),
  startLat: z.number().min(-90).max(90),
  startLng: z.number().min(-180).max(180),
  endLat: z.number().min(-90).max(90),
  endLng: z.number().min(-180).max(180),
  routePolyline: z.any().optional(),
  estimatedDuration: z.number().positive().optional(),
  transportMode: z.string().optional(),
});

const updateLocationSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  accuracy: z.number().positive().optional(),
  speed: z.number().min(0).optional(),
  heading: z.number().min(0).max(360).optional(),
});

const rateCompanionSchema = z.object({
  ratedId: z.string().uuid(),
  score: z.number().min(1).max(5),
  comment: z.string().max(500).optional(),
});

export class SafetyWalkController {
  /**
   * Find potential companions
   */
  async findCompanions(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const validation = findCompanionsSchema.safeParse(req.body);
      if (!validation.success) {
        throw new BadRequestError(validation.error.errors[0].message);
      }

      const { startLat, startLng, endLat, endLng, radius } = validation.data;

      const companions = await safetyWalkService.findCompanions(
        req.user.id,
        startLat,
        startLng,
        endLat,
        endLng,
        radius
      );

      res.json({ success: true, data: { companions } });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Create a walk request
   */
  async createWalkRequest(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const validation = createWalkRequestSchema.safeParse(req.body);
      if (!validation.success) {
        throw new BadRequestError(validation.error.errors[0].message);
      }

      const { companionId, startLat, startLng, endLat, endLng, routePolyline, estimatedDuration, transportMode } =
        validation.data;

      const walk = await safetyWalkService.createWalkRequest(req.user.id, companionId, {
        startLat,
        startLng,
        endLat,
        endLng,
        routePolyline,
        estimatedDuration,
        transportMode,
      });

      res.status(201).json({ success: true, data: { walk } });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Accept a walk request
   */
  async acceptWalk(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const { walkId } = req.params;
      if (!walkId) throw new BadRequestError('Walk ID required');

      const walk = await safetyWalkService.acceptWalk(walkId, req.user.id);

      res.json({ success: true, data: { walk } });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Decline a walk request
   */
  async declineWalk(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const { walkId } = req.params;
      if (!walkId) throw new BadRequestError('Walk ID required');

      const walk = await safetyWalkService.declineWalk(walkId, req.user.id);

      res.json({ success: true, data: { walk } });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Start a walk
   */
  async startWalk(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const { walkId } = req.params;
      if (!walkId) throw new BadRequestError('Walk ID required');

      const walk = await safetyWalkService.startWalk(walkId, req.user.id);

      res.json({ success: true, data: { walk } });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Update location during walk
   */
  async updateLocation(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const { walkId } = req.params;
      if (!walkId) throw new BadRequestError('Walk ID required');

      const validation = updateLocationSchema.safeParse(req.body);
      if (!validation.success) {
        throw new BadRequestError(validation.error.errors[0].message);
      }

      const { latitude, longitude, accuracy, speed, heading } = validation.data;

      const result = await safetyWalkService.updateLocation(
        walkId,
        req.user.id,
        latitude,
        longitude,
        accuracy,
        speed,
        heading
      );

      res.json({ success: true, data: result });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Trigger SOS
   */
  async triggerSOS(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const { walkId } = req.params;
      if (!walkId) throw new BadRequestError('Walk ID required');

      const result = await safetyWalkService.triggerSOS(walkId, req.user.id);

      res.json({ success: true, data: result });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Complete a walk
   */
  async completeWalk(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const { walkId } = req.params;
      if (!walkId) throw new BadRequestError('Walk ID required');

      const result = await safetyWalkService.completeWalk(walkId, req.user.id);

      res.json({ success: true, data: result });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Cancel a walk
   */
  async cancelWalk(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const { walkId } = req.params;
      if (!walkId) throw new BadRequestError('Walk ID required');

      const walk = await safetyWalkService.cancelWalk(walkId, req.user.id);

      res.json({ success: true, data: { walk } });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Rate companion after walk
   */
  async rateCompanion(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const { walkId } = req.params;
      if (!walkId) throw new BadRequestError('Walk ID required');

      const validation = rateCompanionSchema.safeParse(req.body);
      if (!validation.success) {
        throw new BadRequestError(validation.error.errors[0].message);
      }

      const { ratedId, score, comment } = validation.data;

      const rating = await safetyWalkService.rateCompanion(walkId, req.user.id, ratedId, score, comment);

      res.status(201).json({ success: true, data: { rating } });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Get active walk
   */
  async getActiveWalk(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const walk = await safetyWalkService.getActiveWalk(req.user.id);

      res.json({ success: true, data: { walk } });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Get safety score
   */
  async getSafetyScore(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const safetyScore = await safetyWalkService.getSafetyScore(req.user.id);

      res.json({ success: true, data: { safetyScore } });
    } catch (error) {
      next(error);
    }
  }

  /**
   * Get walk history
   */
  async getWalkHistory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const limit = parseInt(req.query.limit as string) || 20;
      const offset = parseInt(req.query.offset as string) || 0;

      const result = await safetyWalkService.getWalkHistory(req.user.id, limit, offset);

      res.json({ success: true, data: result });
    } catch (error) {
      next(error);
    }
  }
}

export const safetyWalkController = new SafetyWalkController();
