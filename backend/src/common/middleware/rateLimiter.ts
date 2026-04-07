import { Request, Response, NextFunction } from 'express';
import rateLimit from 'express-rate-limit';
import { RateLimiterMemory, RateLimiterRedis } from 'rate-limiter-flexible';
import { redis } from '../../index';

// Standard rate limiter for API endpoints
export const rateLimiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000'), // 1 minute
  max: parseInt(process.env.RATE_LIMIT_MAX || '200'), // 200 requests per window
  message: {
    success: false,
    error: 'Too Many Requests',
    message: 'You have exceeded the rate limit. Please try again later.',
  },
  standardHeaders: true,
  legacyHeaders: false,
});

// Strict rate limiter for auth endpoints
export const authRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 15, // 15 attempts per 15 minutes (brute force protection)
  message: {
    success: false,
    error: 'Too Many Requests',
    message: 'Too many authentication attempts. Please try again later.',
  },
  standardHeaders: true,
  legacyHeaders: false,
});

// Create Redis-backed rate limiter for more critical operations
let redisRateLimiter: RateLimiterRedis | RateLimiterMemory;

try {
  redisRateLimiter = new RateLimiterRedis({
    storeClient: redis,
    keyPrefix: 'rl',
    points: 10,
    duration: 1,
    blockDuration: 60,
  });
} catch (err) {
  // Fallback to memory limiter
  redisRateLimiter = new RateLimiterMemory({
    points: 10,
    duration: 1,
    blockDuration: 60,
  });
}

// Middleware for Redis rate limiting
export const strictRateLimiter = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const key = req.ip || 'unknown';
    await redisRateLimiter.consume(key);
    next();
  } catch (err) {
    res.status(429).json({
      success: false,
      error: 'Too Many Requests',
      message: 'Rate limit exceeded. Please slow down.',
    });
  }
};

// Snap sending rate limiter (prevent spam)
export const snapRateLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 30, // 30 snaps per minute
  message: {
    success: false,
    error: 'Too Many Requests',
    message: 'You are sending snaps too quickly. Please wait.',
  },
});

// Story posting rate limiter
export const storyRateLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 50, // 50 stories per hour
  message: {
    success: false,
    error: 'Too Many Requests',
    message: 'You are posting stories too quickly. Please wait.',
  },
});

// Message sending rate limiter
export const messageRateLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 100, // 100 messages per minute
  message: {
    success: false,
    error: 'Too Many Requests',
    message: 'You are sending messages too quickly. Please wait.',
  },
});
