import { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';

// Extend Express Request type to include id
declare global {
  namespace Express {
    interface Request {
      id: string;
    }
  }
}

/**
 * Middleware to generate/propagate request IDs for distributed tracing.
 * - Uses existing X-Request-ID header if present (for upstream tracing)
 * - Otherwise generates a new UUID v4
 * - Attaches to req.id and sets X-Request-ID response header
 */
export const requestIdMiddleware = (
  req: Request,
  res: Response,
  next: NextFunction
): void => {
  // Use existing request ID from header or generate new one
  const requestId = (req.headers['x-request-id'] as string) || crypto.randomUUID();
  
  // Attach to request object
  req.id = requestId;
  
  // Set response header for tracing
  res.setHeader('X-Request-ID', requestId);
  
  next();
};
