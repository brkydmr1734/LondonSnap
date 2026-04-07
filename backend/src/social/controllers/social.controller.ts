import { Request, Response, NextFunction } from 'express';
import { prisma } from '../../index';
import { BadRequestError, NotFoundError, ConflictError } from '../../common/utils/AppError';
import { notificationService } from '../../notifications/services/notification.service';
import { friendEmojiService } from '../services/friend-emoji.service';

export class SocialController {
  async sendFriendRequest(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { userId } = req.params;

      if (userId === req.user.id) throw new BadRequestError('Cannot add yourself');

      // Run all validation checks in parallel
      const [blocked, existing, pendingRequest] = await Promise.all([
        prisma.block.findFirst({
          where: {
            OR: [
              { blockerId: req.user.id, blockedId: userId },
              { blockerId: userId, blockedId: req.user.id },
            ],
          },
        }),
        prisma.friendship.findFirst({
          where: { userId: req.user.id, friendId: userId },
        }),
        prisma.friendRequest.findFirst({
          where: {
            OR: [
              { senderId: req.user.id, receiverId: userId, status: 'PENDING' },
              { senderId: userId, receiverId: req.user.id, status: 'PENDING' },
            ],
          },
        }),
      ]);
      if (blocked) throw new BadRequestError('Cannot send request');
      if (existing) throw new ConflictError('Already friends');
      if (pendingRequest) throw new ConflictError('Request already pending');

      const request = await prisma.friendRequest.create({
        data: { senderId: req.user.id, receiverId: userId },
        include: {
          sender: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        },
      });

      await notificationService.sendPushNotification(userId, {
        type: 'FRIEND_REQUEST',
        title: 'Friend Request',
        body: `${request.sender.displayName} wants to be your friend`,
        data: { requestId: request.id, senderId: req.user.id },
      });

      res.status(201).json({ success: true, data: { request } });
    } catch (error) {
      next(error);
    }
  }

  async acceptFriendRequest(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { requestId } = req.params;

      const request = await prisma.friendRequest.findFirst({
        where: { id: requestId, receiverId: req.user.id, status: 'PENDING' },
      });
      if (!request) throw new NotFoundError('Request not found');

      await prisma.$transaction([
        prisma.friendRequest.update({
          where: { id: requestId },
          data: { status: 'ACCEPTED', respondedAt: new Date() },
        }),
        prisma.friendship.createMany({
          data: [
            { userId: req.user.id, friendId: request.senderId },
            { userId: request.senderId, friendId: req.user.id },
          ],
        }),
      ]);

      // Auto-create direct chat and send notification in parallel
      const currentUserId = req.user.id;
      const chatPromise = prisma.chat.findFirst({
        where: {
          type: 'DIRECT',
          AND: [
            { members: { some: { userId: currentUserId } } },
            { members: { some: { userId: request.senderId } } },
          ],
        },
      }).then(existingChat => {
        if (!existingChat) {
          return prisma.chat.create({
            data: {
              type: 'DIRECT',
              members: {
                createMany: {
                  data: [
                    { userId: currentUserId },
                    { userId: request.senderId },
                  ],
                },
              },
            },
          });
        }
      });

      // Run chat creation and notification in parallel
      await Promise.all([
        chatPromise,
        notificationService.sendPushNotification(request.senderId, {
          type: 'FRIEND_ACCEPTED',
          title: 'Friend Request Accepted',
          body: 'Your friend request was accepted!',
          data: { userId: req.user.id },
        }),
      ]);

      res.json({ success: true, message: 'Friend request accepted' });
    } catch (error) {
      next(error);
    }
  }

  async declineFriendRequest(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { requestId } = req.params;

      await prisma.friendRequest.updateMany({
        where: { id: requestId, receiverId: req.user.id, status: 'PENDING' },
        data: { status: 'DECLINED', respondedAt: new Date() },
      });

      res.json({ success: true, message: 'Friend request declined' });
    } catch (error) {
      next(error);
    }
  }

  async getPendingRequests(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const requests = await prisma.friendRequest.findMany({
        where: { receiverId: req.user.id, status: 'PENDING' },
        include: {
          sender: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true, isVerified: true } },
        },
        orderBy: { createdAt: 'desc' },
      });

      res.json({ success: true, data: { requests } });
    } catch (error) {
      next(error);
    }
  }

  async getSentRequests(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const requests = await prisma.friendRequest.findMany({
        where: { senderId: req.user.id, status: 'PENDING' },
        include: {
          receiver: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        },
        orderBy: { createdAt: 'desc' },
      });

      res.json({ success: true, data: { requests } });
    } catch (error) {
      next(error);
    }
  }

  async getFriends(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const [friendships, friendEmojis] = await Promise.all([
        prisma.friendship.findMany({
          where: { userId: req.user.id },
          include: {
            friend: {
              select: {
                id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true,
                isVerified: true, isOnline: true, lastSeenAt: true,
              },
            },
          },
          orderBy: { friend: { displayName: 'asc' } },
        }),
        friendEmojiService.getFriendEmojis(req.user.id),
      ]);

      const friends = friendships.map(f => {
        const emoji = friendEmojis.get(f.friend.id);
        return {
          ...f.friend,
          level: f.level,
          friendSince: f.createdAt,
          emoji: emoji?.emoji || null,
          emojiLabel: emoji?.label || null,
        };
      });

      res.json({ success: true, data: { friends } });
    } catch (error) {
      next(error);
    }
  }

  async removeFriend(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { friendId } = req.params;

      await prisma.friendship.deleteMany({
        where: {
          OR: [
            { userId: req.user.id, friendId },
            { userId: friendId, friendId: req.user.id },
          ],
        },
      });

      res.json({ success: true, message: 'Friend removed' });
    } catch (error) {
      next(error);
    }
  }

  async updateFriendLevel(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { friendId } = req.params;
      const { level } = req.body;

      await prisma.friendship.updateMany({
        where: { userId: req.user.id, friendId },
        data: { level },
      });

      res.json({ success: true, message: 'Friend level updated' });
    } catch (error) {
      next(error);
    }
  }

  async blockUser(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { userId } = req.params;

      await prisma.$transaction([
        prisma.block.upsert({
          where: { blockerId_blockedId: { blockerId: req.user.id, blockedId: userId } },
          update: {},
          create: { blockerId: req.user.id, blockedId: userId },
        }),
        prisma.friendship.deleteMany({
          where: {
            OR: [
              { userId: req.user.id, friendId: userId },
              { userId, friendId: req.user.id },
            ],
          },
        }),
        prisma.friendRequest.deleteMany({
          where: {
            OR: [
              { senderId: req.user.id, receiverId: userId },
              { senderId: userId, receiverId: req.user.id },
            ],
          },
        }),
      ]);

      res.json({ success: true, message: 'User blocked' });
    } catch (error) {
      next(error);
    }
  }

  async unblockUser(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { userId } = req.params;

      await prisma.block.deleteMany({
        where: { blockerId: req.user.id, blockedId: userId },
      });

      res.json({ success: true, message: 'User unblocked' });
    } catch (error) {
      next(error);
    }
  }

  async getBlockedUsers(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const blocks = await prisma.block.findMany({
        where: { blockerId: req.user.id },
        include: {
          blocked: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        },
      });

      res.json({ success: true, data: { blocked: blocks.map(b => b.blocked) } });
    } catch (error) {
      next(error);
    }
  }

  async getFriendSuggestions(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const [friendIds, blockedIds] = await Promise.all([
        prisma.friendship.findMany({
          where: { userId: req.user.id },
          select: { friendId: true },
        }),
        prisma.block.findMany({
          where: { OR: [{ blockerId: req.user.id }, { blockedId: req.user.id }] },
          select: { blockerId: true, blockedId: true },
        }),
      ]);

      const excludeIds = [
        req.user.id,
        ...friendIds.map(f => f.friendId),
        ...blockedIds.flatMap(b => [b.blockerId, b.blockedId]),
      ];

      // Get users from same university or with mutual friends
      const suggestions = await prisma.user.findMany({
        where: {
          id: { notIn: excludeIds },
          status: 'ACTIVE',
          ...(req.user.universityId && { universityId: req.user.universityId }),
        },
        select: {
          id: true, username: true, displayName: true, avatarUrl: true,
          isVerified: true, isUniversityStudent: true,
          university: { select: { shortName: true } },
        },
        take: 20,
      });

      res.json({ success: true, data: { suggestions } });
    } catch (error) {
      next(error);
    }
  }

  async getMutualFriends(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { userId } = req.params;

      const [myFriends, theirFriends] = await Promise.all([
        prisma.friendship.findMany({
          where: { userId: req.user.id },
          select: { friendId: true },
        }),
        prisma.friendship.findMany({
          where: { userId },
          select: { friendId: true },
        }),
      ]);

      const myFriendIds = new Set(myFriends.map(f => f.friendId));
      const mutualIds = theirFriends.filter(f => myFriendIds.has(f.friendId)).map(f => f.friendId);

      const mutualFriends = await prisma.user.findMany({
        where: { id: { in: mutualIds } },
        select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true },
      });

      res.json({ success: true, data: { mutualFriends } });
    } catch (error) {
      next(error);
    }
  }

  async getSnapScore(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const user = await prisma.user.findUnique({
        where: { id: req.user.id },
        select: { snapScore: true },
      });

      if (!user) throw new NotFoundError('User not found');

      res.json({ success: true, data: { snapScore: user.snapScore } });
    } catch (error) {
      next(error);
    }
  }
}

export const socialController = new SocialController();
