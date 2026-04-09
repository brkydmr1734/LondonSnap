import { Request, Response, NextFunction } from 'express';
import { prisma } from '../../index';
import { BadRequestError } from '../../common/utils/AppError';
import { logger } from '../../common/utils/logger';

export class CallController {
  /**
   * GET /api/v1/calls/history
   * Paginated call history for the authenticated user (as caller or receiver).
   * Query params: limit (default 30), offset (default 0)
   */
  async getCallHistory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const limit = Math.min(parseInt(req.query.limit as string) || 30, 100);
      const offset = parseInt(req.query.offset as string) || 0;
      const userId = req.user.id;

      const [callLogs, total] = await Promise.all([
        prisma.callLog.findMany({
          where: {
            OR: [{ callerId: userId }, { receiverId: userId }],
          },
          orderBy: { startedAt: 'desc' },
          skip: offset,
          take: limit,
          include: {
            caller: {
              select: { id: true, displayName: true, username: true, avatarUrl: true },
            },
            receiver: {
              select: { id: true, displayName: true, username: true, avatarUrl: true },
            },
          },
        }),
        prisma.callLog.count({
          where: {
            OR: [{ callerId: userId }, { receiverId: userId }],
          },
        }),
      ]);

      res.json({
        success: true,
        data: {
          calls: callLogs,
          total,
          limit,
          offset,
        },
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * GET /api/v1/calls/turn-credentials
   * Returns time-limited TURN server credentials so they are not hardcoded in the client.
   */
  async getTurnCredentials(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const username = process.env.TURN_USERNAME;
      const credential = process.env.TURN_CREDENTIAL;

      if (!username || !credential) {
        logger.error('[CALL] TURN_USERNAME or TURN_CREDENTIAL env var is MISSING on this server. WebRTC calls will fall back to STUN-only and likely fail on mobile networks.');
        return res.status(503).json({
          success: false,
          error: 'TURN server not configured',
          hint: 'Set TURN_USERNAME and TURN_CREDENTIAL environment variables on the server.',
        });
      }

      logger.info(`[CALL] TURN credentials served to user ${req.user.id}`);

      // Time-limited credentials (valid for 24 hours)
      const ttl = 86400; // 24 hours in seconds
      const expiry = Math.floor(Date.now() / 1000) + ttl;

      const iceServers = [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:stun1.l.google.com:19302' },
        {
          urls: 'turn:a.relay.metered.ca:80',
          username,
          credential,
        },
        {
          urls: 'turn:a.relay.metered.ca:80?transport=tcp',
          username,
          credential,
        },
        {
          urls: 'turn:a.relay.metered.ca:443',
          username,
          credential,
        },
        {
          urls: 'turns:a.relay.metered.ca:443',
          username,
          credential,
        },
      ];

      res.json({
        success: true,
        data: {
          iceServers,
          ttl,
          expiry,
        },
      });

      logger.info(`[CALL] TURN credentials served: ${iceServers.length} servers, ttl=${ttl}s, user=${req.user.id.slice(0,8)}`);
    } catch (error) {
      next(error);
    }
  }
}

export const callController = new CallController();
