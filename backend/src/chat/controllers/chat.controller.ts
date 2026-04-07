import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../../index';
import { BadRequestError, NotFoundError, ForbiddenError } from '../../common/utils/AppError';
import { notificationService } from '../../notifications/services/notification.service';
import { websocketService } from '../services/websocket.service';
import { chatService } from '../services/chat.service';

export class ChatController {
  // Get all chats
  async getChats(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      // Ensure all friends have a direct chat (auto-create missing ones)
      // Parallelize: fetch friends and existing chats simultaneously
      const [friends, existingDirectChats] = await Promise.all([
        prisma.friendship.findMany({
          where: { userId: req.user.id },
          select: { friendId: true },
        }),
        prisma.chat.findMany({
          where: {
            type: 'DIRECT',
            members: { some: { userId: req.user.id } },
          },
          include: { members: { select: { userId: true } } },
        }),
      ]);

      if (friends.length > 0) {
        const friendsWithChat = new Set<string>();
        for (const chat of existingDirectChats) {
          const memberIds = chat.members.map(m => m.userId);
          if (memberIds.length === 2) {
            const otherUser = memberIds.find(id => id !== req.user!.id);
            if (otherUser) friendsWithChat.add(otherUser);
          }
        }

        const friendsWithoutChat = friends
          .filter(f => !friendsWithChat.has(f.friendId))
          .map(f => f.friendId);

        // Create missing direct chats in parallel
        if (friendsWithoutChat.length > 0) {
          await Promise.all(
            friendsWithoutChat.map(friendId =>
              prisma.chat.create({
                data: {
                  type: 'DIRECT',
                  members: {
                    createMany: {
                      data: [{ userId: req.user!.id }, { userId: friendId }],
                    },
                  },
                },
              })
            )
          );
        }
      }

      const chats = await prisma.chat.findMany({
        where: {
          members: {
            some: { userId: req.user.id, leftAt: null, deletedAt: null },
          },
        },
        include: {
          members: {
            where: { leftAt: null },
            include: {
              user: {
                select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true, isOnline: true },
              },
            },
          },
          messages: {
            take: 1,
            orderBy: { createdAt: 'desc' },
            include: {
              sender: { select: { id: true, displayName: true } },
            },
          },
        },
        orderBy: { updatedAt: 'desc' },
      });

      // Batch calculate unread counts to avoid N+1 queries
      const chatIds = chats.map(c => c.id);
      const userId = req.user.id;

      // Get user's membership info for all chats (lastReadAt, joinedAt)
      const membershipMap = new Map<string, { lastReadAt: Date | null; joinedAt: Date }>();
      for (const chat of chats) {
        const member = chat.members.find(m => m.userId === userId);
        if (member) {
          membershipMap.set(chat.id, { lastReadAt: member.lastReadAt, joinedAt: member.joinedAt });
        }
      }

      // Batch count unread messages using raw query for efficiency
      const unreadCounts = await prisma.$queryRaw<Array<{ chatId: string; count: bigint }>>`
        SELECT m."chatId", COUNT(m.id) as count
        FROM "Message" m
        INNER JOIN "ChatMember" cm ON cm."chatId" = m."chatId" AND cm."userId" = ${userId}
        WHERE m."chatId" = ANY(${chatIds})
          AND m."isDeleted" = false
          AND m."senderId" != ${userId}
          AND m."createdAt" > COALESCE(cm."lastReadAt", cm."joinedAt")
        GROUP BY m."chatId"
      `;

      const unreadCountMap = new Map<string, number>();
      for (const row of unreadCounts) {
        unreadCountMap.set(row.chatId, Number(row.count));
      }

      const formattedChats = chats.map(chat => ({
        ...chat,
        otherMembers: chat.members.filter(m => m.userId !== req.user!.id),
        lastMessage: chat.messages[0],
        unreadCount: unreadCountMap.get(chat.id) || 0,
      }));

      res.json({ success: true, data: { chats: formattedChats } });
    } catch (error) {
      next(error);
    }
  }

  // Create group chat
  async createChat(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const { name, memberIds, imageUrl } = req.body;
      if (!memberIds?.length) throw new BadRequestError('Members required');

      const allMemberIds = [...new Set([req.user.id, ...memberIds])];

      const chat = await prisma.chat.create({
        data: {
          type: 'GROUP',
          name,
          imageUrl,
          members: {
            createMany: {
              data: allMemberIds.map((userId, i) => ({
                userId,
                role: i === 0 ? 'OWNER' : 'MEMBER',
              })),
            },
          },
        },
        include: {
          members: {
            include: {
              user: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
            },
          },
        },
      });

      res.status(201).json({ success: true, data: { chat } });
    } catch (error) {
      next(error);
    }
  }

  // Get or create direct chat
  async getOrCreateDirectChat(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { userId } = req.params;

      // Find existing chat
      let chat = await prisma.chat.findFirst({
        where: {
          type: 'DIRECT',
          AND: [
            { members: { some: { userId: req.user.id } } },
            { members: { some: { userId } } },
          ],
        },
        include: {
          members: {
            include: {
              user: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true, isOnline: true } },
            },
          },
        },
      });

      if (!chat) {
        chat = await prisma.chat.create({
          data: {
            type: 'DIRECT',
            members: {
              createMany: {
                data: [{ userId: req.user.id }, { userId }],
              },
            },
          },
          include: {
            members: {
              include: {
                user: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true, isOnline: true } },
              },
            },
          },
        });
      }

      res.json({ success: true, data: { chat } });
    } catch (error) {
      next(error);
    }
  }

  // Get chat by ID
  async getChatById(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const chat = await prisma.chat.findFirst({
        where: {
          id: req.params.chatId,
          members: { some: { userId: req.user.id, leftAt: null } },
        },
        include: {
          members: {
            where: { leftAt: null },
            include: {
              user: { select: { id: true, username: true, displayName: true, avatarUrl: true, isOnline: true } },
            },
          },
        },
      });

      if (!chat) throw new NotFoundError('Chat not found');
      res.json({ success: true, data: { chat } });
    } catch (error) {
      next(error);
    }
  }

  // Get messages
  async getMessages(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId } = req.params;
      const { limit = 50, before, after } = req.query;

      const member = await prisma.chatMember.findUnique({
        where: { chatId_userId: { chatId, userId: req.user.id } },
      });
      if (!member || member.leftAt) throw new ForbiddenError('Not a member');

      const dateFilter: any = {};
      if (before) dateFilter.lt = new Date(before as string);
      if (after) dateFilter.gt = new Date(after as string);

      const messages = await prisma.message.findMany({
        where: {
          chatId,
          isDeleted: false,
          ...(Object.keys(dateFilter).length > 0 && { createdAt: dateFilter }),
        },
        include: {
          sender: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
          replyTo: {
            select: {
              id: true, content: true, type: true,
              sender: { select: { id: true, displayName: true } },
            },
          },
        },
        take: Number(limit),
        orderBy: { createdAt: 'desc' },
      });

      res.json({ success: true, data: { messages: messages.reverse() } });
    } catch (error) {
      next(error);
    }
  }

  // Send message
  async sendMessage(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId } = req.params;
      const { type, content, mediaUrl, mediaType, replyToId } = req.body;

      // Check membership and get chat settings in parallel
      const [member, chat] = await Promise.all([
        prisma.chatMember.findUnique({
          where: { chatId_userId: { chatId, userId: req.user.id } },
        }),
        prisma.chat.findUnique({
          where: { id: chatId },
          select: { isDisappearing: true, disappearAfter: true },
        }),
      ]);
      if (!member || member.leftAt) throw new ForbiddenError('Not a member');

      // Calculate expiresAt for disappearing chats
      let expiresAt: Date | undefined;
      if (chat?.isDisappearing && chat.disappearAfter != null) {
        expiresAt = new Date(Date.now() + chat.disappearAfter * 1000);
      }

      const message = await prisma.message.create({
        data: { chatId, senderId: req.user.id, type, content, mediaUrl, mediaType, replyToId, expiresAt },
        include: {
          sender: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
          replyTo: {
            select: {
              id: true, content: true, type: true,
              sender: { select: { id: true, displayName: true } },
            },
          },
        },
      });

      // Fire-and-forget: update chat timestamp without blocking response
      prisma.chat.update({
        where: { id: chatId },
        data: { lastMessageAt: new Date() },
      }).catch(() => {});

      // Emit to WebSocket for real-time delivery
      websocketService.emitNewMessage(chatId, message);

      res.status(201).json({ success: true, data: { message } });
    } catch (error) {
      next(error);
    }
  }

  // Edit message
  async editMessage(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId, messageId } = req.params;
      const { content } = req.body;

      const message = await prisma.message.findFirst({
        where: { id: messageId, senderId: req.user.id },
      });
      if (!message) throw new NotFoundError('Message not found');

      const updated = await prisma.message.update({
        where: { id: messageId },
        data: { content, isEdited: true },
      });

      // Emit to WebSocket for real-time edit notification
      websocketService.emitMessageEdited(message.chatId, {
        id: updated.id,
        content: updated.content,
        isEdited: updated.isEdited,
        updatedAt: updated.updatedAt,
      });

      res.json({ success: true, data: { message: updated } });
    } catch (error) {
      next(error);
    }
  }

  // Delete message
  async deleteMessage(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { messageId } = req.params;

      const message = await prisma.message.findFirst({
        where: { id: messageId, senderId: req.user.id },
      });
      if (!message) throw new NotFoundError('Message not found');

      await prisma.message.update({
        where: { id: messageId },
        data: { isDeleted: true, content: null, mediaUrl: null },
      });

      // Emit to WebSocket for real-time deletion notification
      websocketService.emitMessageDeleted(message.chatId, messageId);

      res.json({ success: true, message: 'Message deleted' });
    } catch (error) {
      next(error);
    }
  }

  // React to message (toggle reaction)
  async reactToMessage(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId, messageId } = req.params;
      const { emoji } = req.body;

      if (!emoji || typeof emoji !== 'string') {
        throw new BadRequestError('Emoji is required');
      }

      // Verify membership
      const member = await prisma.chatMember.findUnique({
        where: { chatId_userId: { chatId, userId: req.user.id } },
      });
      if (!member || member.leftAt) throw new ForbiddenError('Not a member');

      // Verify message exists in this chat
      const message = await prisma.message.findFirst({
        where: { id: messageId, chatId, isDeleted: false },
      });
      if (!message) throw new NotFoundError('Message not found');

      // Check if reaction already exists (toggle behavior)
      const existingReaction = await prisma.messageReaction.findUnique({
        where: {
          messageId_userId_emoji: { messageId, userId: req.user.id, emoji },
        },
      });

      let action: 'add' | 'remove';
      if (existingReaction) {
        // Remove the reaction (toggle off)
        await prisma.messageReaction.delete({
          where: { id: existingReaction.id },
        });
        action = 'remove';
      } else {
        // Add the reaction
        await prisma.messageReaction.create({
          data: { messageId, userId: req.user.id, emoji },
        });
        action = 'add';
      }

      // Emit WebSocket event for real-time update
      websocketService.emitMessageReaction(chatId, {
        messageId,
        userId: req.user.id,
        emoji,
        action,
      });

      res.json({ success: true, data: { action, emoji } });
    } catch (error) {
      next(error);
    }
  }

  // Update chat
  async updateChat(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId } = req.params;
      const { name, imageUrl, isDisappearing, disappearAfter } = req.body;

      const member = await prisma.chatMember.findUnique({
        where: { chatId_userId: { chatId, userId: req.user.id } },
      });
      if (!member || member.leftAt) throw new ForbiddenError('Not a member');

      // Name/image changes require OWNER or ADMIN role (group settings)
      if ((name !== undefined || imageUrl !== undefined) && !['OWNER', 'ADMIN'].includes(member.role)) {
        throw new ForbiddenError('Insufficient permissions');
      }

      const updateData: Record<string, any> = {};
      if (name !== undefined) updateData.name = name;
      if (imageUrl !== undefined) updateData.imageUrl = imageUrl;
      if (isDisappearing !== undefined) updateData.isDisappearing = isDisappearing;
      if (disappearAfter !== undefined) updateData.disappearAfter = disappearAfter;
      // Allow explicit null to clear disappearAfter
      if ('disappearAfter' in req.body) updateData.disappearAfter = disappearAfter;

      const chat = await prisma.chat.update({
        where: { id: chatId },
        data: updateData,
      });

      res.json({ success: true, data: { chat } });
    } catch (error) {
      next(error);
    }
  }

  // Add member
  async addMember(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId } = req.params;
      const { userId } = req.body;

      const member = await prisma.chatMember.findUnique({
        where: { chatId_userId: { chatId, userId: req.user.id } },
      });
      if (!member || !['OWNER', 'ADMIN'].includes(member.role)) {
        throw new ForbiddenError('Insufficient permissions');
      }

      await prisma.chatMember.upsert({
        where: { chatId_userId: { chatId, userId } },
        update: { leftAt: null },
        create: { chatId, userId },
      });

      res.json({ success: true, message: 'Member added' });
    } catch (error) {
      next(error);
    }
  }

  // Remove member
  async removeMember(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId, userId } = req.params;

      const member = await prisma.chatMember.findUnique({
        where: { chatId_userId: { chatId, userId: req.user.id } },
      });
      if (!member || !['OWNER', 'ADMIN'].includes(member.role)) {
        throw new ForbiddenError('Insufficient permissions');
      }

      await prisma.chatMember.update({
        where: { chatId_userId: { chatId, userId } },
        data: { leftAt: new Date() },
      });

      res.json({ success: true, message: 'Member removed' });
    } catch (error) {
      next(error);
    }
  }

  // Leave chat
  async leaveChat(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId } = req.params;

      await prisma.chatMember.update({
        where: { chatId_userId: { chatId, userId: req.user.id } },
        data: { leftAt: new Date() },
      });

      res.json({ success: true, message: 'Left chat' });
    } catch (error) {
      next(error);
    }
  }

  // Mute chat
  async muteChat(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId } = req.params;
      const { until } = req.body;

      await prisma.chatMember.update({
        where: { chatId_userId: { chatId, userId: req.user.id } },
        data: { isMuted: true, mutedUntil: until ? new Date(until) : null },
      });

      res.json({ success: true, message: 'Chat muted' });
    } catch (error) {
      next(error);
    }
  }

  // Unmute chat
  async unmuteChat(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId } = req.params;

      await prisma.chatMember.update({
        where: { chatId_userId: { chatId, userId: req.user.id } },
        data: { isMuted: false, mutedUntil: null },
      });

      res.json({ success: true, message: 'Chat unmuted' });
    } catch (error) {
      next(error);
    }
  }

  // Mark messages as read
  async markAsRead(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId } = req.params;
      const { messageId } = req.body;

      const member = await prisma.chatMember.findUnique({
        where: { chatId_userId: { chatId, userId: req.user.id } },
      });
      if (!member || member.leftAt) throw new ForbiddenError('Not a member');

      // Fire both in parallel
      const ops: Promise<any>[] = [
        prisma.chatMember.update({
          where: { chatId_userId: { chatId, userId: req.user.id } },
          data: { lastReadAt: new Date() },
        }),
      ];
      if (messageId) {
        ops.push(prisma.messageReadReceipt.upsert({
          where: { messageId_userId: { messageId, userId: req.user.id } },
          update: { readAt: new Date() },
          create: { messageId, userId: req.user.id, readAt: new Date() },
        }));
      }
      await Promise.all(ops);

      // Emit read receipt via WebSocket
      if (messageId) {
        const message = await prisma.message.findUnique({
          where: { id: messageId },
          select: { senderId: true },
        });
        if (message && message.senderId !== req.user.id) {
          websocketService.emitMessageRead(message.senderId, {
            messageId,
            chatId,
            userId: req.user.id,
          });
        }
      }

      res.json({ success: true, message: 'Marked as read' });
    } catch (error) {
      next(error);
    }
  }

  // Delete chat for current user
  async deleteChat(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId } = req.params;

      const result = await chatService.deleteChat(chatId, req.user.id);

      res.json({
        success: true,
        message: result.hardDeleted ? 'Chat permanently deleted' : 'Chat deleted',
        data: { hardDeleted: result.hardDeleted },
      });
    } catch (error) {
      if (error instanceof Error && error.message === 'Not a member of this chat') {
        return next(new ForbiddenError('Not a member of this chat'));
      }
      next(error);
    }
  }

  // Mark messages as delivered
  async markAsDelivered(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { chatId } = req.params;
      const { messageIds } = req.body;

      if (!messageIds || !Array.isArray(messageIds) || messageIds.length === 0) {
        throw new BadRequestError('messageIds array is required');
      }

      const result = await chatService.markMessagesDelivered(chatId, messageIds, req.user.id);

      res.json({
        success: true,
        message: 'Messages marked as delivered',
        data: { deliveredCount: result.deliveredCount },
      });
    } catch (error) {
      if (error instanceof Error && error.message === 'Not a member of this chat') {
        return next(new ForbiddenError('Not a member of this chat'));
      }
      next(error);
    }
  }
}

export const chatController = new ChatController();

