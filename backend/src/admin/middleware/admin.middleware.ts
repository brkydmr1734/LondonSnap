import { Request, Response, NextFunction } from 'express';
import { prisma } from '../../index';
import { UnauthorizedError, ForbiddenError } from '../../common/utils/AppError';
import { authCache } from '../../common/utils/cache';

export const requireAdmin = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    if (!req.user) {
      throw new UnauthorizedError('Authentication required');
    }

    // Check admin status from cache first
    const cacheKey = `admin:${req.user.id}`;
    let isAdmin = authCache.get<boolean>(cacheKey);

    if (isAdmin === undefined) {
      const user = await prisma.user.findUnique({
        where: { id: req.user.id },
        select: { isAdmin: true },
      });
      isAdmin = user?.isAdmin || false;
      authCache.set(cacheKey, isAdmin, 60_000); // cache for 60s
    }

    if (!isAdmin) {
      throw new ForbiddenError('Admin access required');
    }

    next();
  } catch (error) {
    next(error);
  }
};
