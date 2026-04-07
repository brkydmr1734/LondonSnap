import { Request, Response, NextFunction } from 'express';
import { prisma } from '../../index';
import { ForbiddenError, NotFoundError, BadRequestError } from '../../common/utils/AppError';

/**
 * Middleware to validate that the requesting user is a participant
 * (requester or companion) of the specified walk.
 * 
 * Attaches the walk object to req.walk for downstream handlers.
 */
export const validateWalkParticipant = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    if (!req.user) {
      throw new BadRequestError('Auth required');
    }

    const { walkId } = req.params;
    if (!walkId) {
      throw new BadRequestError('Walk ID required');
    }

    const walk = await prisma.safetyWalk.findUnique({
      where: { id: walkId },
      include: {
        requester: {
          select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true },
        },
        companion: {
          select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true },
        },
      },
    });

    if (!walk) {
      throw new NotFoundError('Walk not found');
    }

    if (walk.requesterId !== req.user.id && walk.companionId !== req.user.id) {
      throw new ForbiddenError('You are not a participant of this walk');
    }

    // Attach walk to request for downstream handlers
    (req as any).walk = walk;

    next();
  } catch (error) {
    next(error);
  }
};

/**
 * Middleware to ensure walk is in active state
 */
export const requireActiveWalk = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const walk = (req as any).walk;

    if (!walk) {
      throw new BadRequestError('Walk not loaded - use validateWalkParticipant first');
    }

    if (walk.status !== 'ACTIVE') {
      throw new BadRequestError('Walk is not active');
    }

    next();
  } catch (error) {
    next(error);
  }
};

/**
 * Middleware to ensure walk is in pending state (for accept/decline)
 */
export const requirePendingWalk = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const walk = (req as any).walk;

    if (!walk) {
      throw new BadRequestError('Walk not loaded - use validateWalkParticipant first');
    }

    if (walk.status !== 'PENDING') {
      throw new BadRequestError('Walk is not pending');
    }

    next();
  } catch (error) {
    next(error);
  }
};

/**
 * Middleware to ensure user is the companion (for accept/decline)
 */
export const requireCompanion = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    if (!req.user) {
      throw new BadRequestError('Auth required');
    }

    const walk = (req as any).walk;

    if (!walk) {
      throw new BadRequestError('Walk not loaded - use validateWalkParticipant first');
    }

    if (walk.companionId !== req.user.id) {
      throw new ForbiddenError('Only the companion can perform this action');
    }

    next();
  } catch (error) {
    next(error);
  }
};
