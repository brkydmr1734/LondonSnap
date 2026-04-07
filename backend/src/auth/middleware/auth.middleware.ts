import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { prisma } from '../../index';
import { UnauthorizedError } from '../../common/utils/AppError';
import { AuthenticatedUser, JWTPayload } from '../models/auth.types';
import { authCache, CACHE_TTL } from '../../common/utils/cache';

declare global {
  namespace Express {
    interface Request {
      user?: AuthenticatedUser;
      token?: string;
    }
  }
}

const JWT_SECRET = process.env.JWT_SECRET!;

export const authMiddleware = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new UnauthorizedError('No token provided');
    }

    const token = authHeader.split(' ')[1];

    // Verify token
    const decoded = jwt.verify(token, JWT_SECRET) as JWTPayload;

    if (decoded.type !== 'access') {
      throw new UnauthorizedError('Invalid token type');
    }

    // Check cache first — eliminates 2 DB queries for repeated requests
    const userCacheKey = `user:${decoded.userId}`;
    const sessionCacheKey = `session:${token}`;
    let user = authCache.get<any>(userCacheKey);
    let session = authCache.get<any>(sessionCacheKey);

    if (!user || !session) {
      const [dbUser, dbSession] = await Promise.all([
        user ? Promise.resolve(user) : prisma.user.findUnique({
          where: { id: decoded.userId },
          select: {
            id: true, email: true, username: true, displayName: true,
            avatarUrl: true, avatarConfig: true, isVerified: true, isUniversityStudent: true,
            universityId: true, status: true,
            university: { select: { id: true, name: true, shortName: true, domain: true, logoUrl: true } },
          },
        }),
        session ? Promise.resolve(session) : prisma.session.findUnique({
          where: { token },
        }),
      ]);
      user = dbUser;
      session = dbSession;
      if (user) authCache.set(userCacheKey, user, CACHE_TTL.AUTH_USER);
      if (session) authCache.set(sessionCacheKey, session, CACHE_TTL.AUTH_SESSION);
    }

    if (!user) {
      throw new UnauthorizedError('User not found');
    }

    if (user.status !== 'ACTIVE') {
      throw new UnauthorizedError('Account is not active');
    }

    if (!session || session.expiresAt < new Date()) {
      throw new UnauthorizedError('Session expired');
    }

    // Throttle timestamp updates — at most once per 30s per user
    const updateKey = `lastUpdate:${user.id}`;
    if (!authCache.get(updateKey)) {
      authCache.set(updateKey, true, 30_000);
      Promise.all([
        prisma.session.update({ where: { id: session.id }, data: { lastUsedAt: new Date() } }),
        prisma.user.update({ where: { id: user.id }, data: { lastSeenAt: new Date(), isOnline: true } }),
      ]).catch(() => {});
    }

    req.user = user as AuthenticatedUser;
    req.token = token;

    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      return next(new UnauthorizedError('Invalid token'));
    }
    if (error instanceof jwt.TokenExpiredError) {
      return next(new UnauthorizedError('Token expired'));
    }
    next(error);
  }
};

// Optional auth - doesn't fail if no token
export const optionalAuthMiddleware = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return next();
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, JWT_SECRET) as JWTPayload;

    if (decoded.type === 'access') {
      const user = await prisma.user.findUnique({
        where: { id: decoded.userId },
        select: {
          id: true,
          email: true,
          username: true,
          displayName: true,
          avatarUrl: true,
          avatarConfig: true,
          isVerified: true,
          isUniversityStudent: true,
          universityId: true,
          status: true,
          university: { select: { id: true, name: true, shortName: true, domain: true, logoUrl: true } },
        },
      });

      if (user && user.status === 'ACTIVE') {
        req.user = user as AuthenticatedUser;
        req.token = token;
      }
    }

    next();
  } catch (error) {
    // Ignore errors for optional auth
    next();
  }
};

// Require verified university student
export const universityStudentMiddleware = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  if (!req.user) {
    return next(new UnauthorizedError('Authentication required'));
  }

  if (!req.user.isUniversityStudent) {
    return next(new UnauthorizedError('University student verification required'));
  }

  next();
};

// Require verified email
export const verifiedEmailMiddleware = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  if (!req.user) {
    return next(new UnauthorizedError('Authentication required'));
  }

  const user = await prisma.user.findUnique({
    where: { id: req.user.id },
    select: { emailVerified: true },
  });

  if (!user?.emailVerified) {
    return next(new UnauthorizedError('Email verification required'));
  }

  next();
};
