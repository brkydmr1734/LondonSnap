import dayjs from 'dayjs';
import { prisma } from '../../index';
import { BadRequestError, NotFoundError, ForbiddenError } from '../../common/utils/AppError';
import { notificationService } from '../../notifications/services/notification.service';
import { friendEmojiService } from '../../social/services/friend-emoji.service';
import { chatService } from '../../chat/services/chat.service';

export class SnapService {
  // Send a snap
  async sendSnap(
    senderId: string,
    recipientIds: string[],
    data: {
      mediaUrl: string;
      mediaType: 'IMAGE' | 'VIDEO';
      thumbnailUrl?: string;
      duration?: number;
      hasAudio?: boolean;
      caption?: string;
      drawingData?: any;
      stickers?: any;
      filters?: any;
      viewDuration?: number;
      isReplayable?: boolean;
    }
  ) {
    // Verify recipients are friends
    const friendships = await prisma.friendship.findMany({
      where: {
        userId: senderId,
        friendId: { in: recipientIds },
      },
    });

    const validRecipientIds = friendships.map(f => f.friendId);
    
    if (validRecipientIds.length === 0) {
      throw new BadRequestError('No valid recipients');
    }

    // Create snap
    const snap = await prisma.snap.create({
      data: {
        senderId,
        mediaUrl: data.mediaUrl,
        mediaType: data.mediaType,
        thumbnailUrl: data.thumbnailUrl,
        duration: data.duration,
        hasAudio: data.hasAudio || false,
        caption: data.caption,
        drawingData: data.drawingData,
        stickers: data.stickers,
        filters: data.filters,
        viewDuration: data.viewDuration || 5,
        isReplayable: data.isReplayable || false,
        expiresAt: dayjs().add(24, 'hours').toDate(),
        recipients: {
          createMany: {
            data: validRecipientIds.map(userId => ({
              userId,
              status: 'PENDING',
            })),
          },
        },
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true,
            displayName: true,
            avatarUrl: true,
          },
        },
        recipients: {
          select: {
            userId: true,
            status: true,
          },
        },
      },
    });

    // Update streaks in parallel
    await Promise.all(validRecipientIds.map(recipientId => this.updateStreak(senderId, recipientId)));

    // Fire-and-forget: increment snap scores (don't block response)
    this.incrementSnapScores(senderId, validRecipientIds).catch(() => {});

    // Fire-and-forget: invalidate emoji caches for affected users
    friendEmojiService.invalidateCache(senderId);
    validRecipientIds.forEach(id => friendEmojiService.invalidateCache(id));

    // Fire-and-forget: send push notifications in parallel without blocking response
    Promise.all(validRecipientIds.map(recipientId =>
      notificationService.sendPushNotification(recipientId, {
        type: 'SNAP_RECEIVED',
        title: 'New Snap',
        body: `${snap.sender.displayName} sent you a snap`,
        data: { snapId: snap.id, senderId },
      })
    )).catch(() => {});

    // Fire-and-forget: create SNAP messages in chat for each recipient
    chatService.createSnapMessagesForRecipients(
      senderId,
      validRecipientIds,
      snap.id,
      data.mediaType
    ).catch((err) => console.error('Failed to create snap messages:', err));

    return snap;
  }

  // Get received snaps
  async getReceivedSnaps(userId: string) {
    const snaps = await prisma.snapRecipient.findMany({
      where: {
        userId,
        status: { in: ['PENDING', 'DELIVERED'] },
        snap: {
          expiresAt: { gt: new Date() },
        },
      },
      include: {
        snap: {
          include: {
            sender: {
              select: {
                id: true,
                username: true,
                displayName: true,
                avatarUrl: true,
              },
            },
          },
        },
      },
      orderBy: { snap: { createdAt: 'desc' } },
    });

    // Mark as delivered
    const pendingIds = snaps
      .filter(s => s.status === 'PENDING')
      .map(s => s.id);

    if (pendingIds.length > 0) {
      await prisma.snapRecipient.updateMany({
        where: { id: { in: pendingIds } },
        data: {
          status: 'DELIVERED',
          deliveredAt: new Date(),
        },
      });

      // Fire-and-forget: update snap message status to DELIVERED for each pending snap
      const pendingSnaps = snaps.filter(s => s.status === 'PENDING');
      for (const pendingSnap of pendingSnaps) {
        chatService.updateSnapMessageStatus(pendingSnap.snapId, 'DELIVERED')
          .catch(() => {});
      }
    }

    return snaps;
  }

  // Get sent snaps
  async getSentSnaps(userId: string) {
    const snaps = await prisma.snap.findMany({
      where: {
        senderId: userId,
        expiresAt: { gt: new Date() },
      },
      include: {
        recipients: {
          include: {
            user: {
              select: {
                id: true,
                username: true,
                displayName: true,
                avatarUrl: true,
              },
            },
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return snaps;
  }

  // Open a snap
  async openSnap(userId: string, snapId: string) {
    // First check if user is the recipient
    const recipient = await prisma.snapRecipient.findFirst({
      where: {
        snapId,
        userId,
      },
      include: {
        snap: {
          include: {
            sender: {
              select: {
                id: true,
                username: true,
                displayName: true,
              },
            },
          },
        },
      },
    });

    // If not a recipient, check if user is the sender (allow sender to view their own snap)
    if (!recipient) {
      const snap = await prisma.snap.findFirst({
        where: {
          id: snapId,
          senderId: userId,
        },
        include: {
          sender: {
            select: {
              id: true,
              username: true,
              displayName: true,
            },
          },
        },
      });

      if (!snap) {
        throw new NotFoundError('Snap not found');
      }

      // Sender can always view their own snap (no status update needed)
      return {
        snap,
        viewDuration: snap.viewDuration,
        isReplay: false,
      };
    }

    if (recipient.snap.expiresAt < new Date()) {
      throw new ForbiddenError('Snap expired');
    }

    let newStatus: 'OPENED' | 'REPLAYED';
    let isReplay = false;

    if (!recipient.openedAt) {
      // First open
      await prisma.snapRecipient.update({
        where: { id: recipient.id },
        data: {
          status: 'OPENED',
          openedAt: new Date(),
        },
      });
      newStatus = 'OPENED';
    } else if (recipient.replayCount < 1) {
      // Allow exactly 1 replay (regardless of isReplayable flag)
      await prisma.snapRecipient.update({
        where: { id: recipient.id },
        data: {
          status: 'REPLAYED',
          replayedAt: new Date(),
          replayCount: { increment: 1 },
        },
      });
      newStatus = 'REPLAYED';
      isReplay = true;
    } else {
      // Already replayed once
      throw new ForbiddenError('Snap already replayed');
    }

    // Notify sender
    await notificationService.sendPushNotification(recipient.snap.senderId, {
      type: 'SNAP_OPENED',
      title: 'Snap Opened',
      body: `${recipient.snap.sender.displayName} opened your snap`,
      data: { snapId, userId },
    });

    // Fire-and-forget: update snap message status in chat (also emits WebSocket event)
    chatService.updateSnapMessageStatus(snapId, newStatus)
      .catch((err) => console.error('Failed to update snap message status:', err));

    return {
      snap: recipient.snap,
      viewDuration: recipient.snap.viewDuration,
      isReplay,
    };
  }

  // Report screenshot
  async reportScreenshot(userId: string, snapId: string) {
    const recipient = await prisma.snapRecipient.findFirst({
      where: {
        snapId,
        userId,
      },
      include: {
        snap: true,
      },
    });

    if (!recipient) {
      throw new NotFoundError('Snap not found');
    }

    // Record screenshot
    await prisma.$transaction([
      prisma.snapRecipient.update({
        where: { id: recipient.id },
        data: { screenshotAt: new Date() },
      }),
      prisma.snapScreenshot.create({
        data: {
          snapId,
          userId,
        },
      }),
    ]);

    // Notify sender
    await notificationService.sendPushNotification(recipient.snap.senderId, {
      type: 'SNAP_SCREENSHOT',
      title: 'Screenshot Taken',
      body: 'Someone took a screenshot of your snap',
      data: { snapId, userId },
    });

    // Fire-and-forget: update snap message status in chat
    chatService.updateSnapMessageStatus(snapId, 'SCREENSHOT')
      .catch((err) => console.error('Failed to update snap message status for screenshot:', err));

    return { success: true };
  }

  // Get snap status
  async getSnapStatus(userId: string, snapId: string) {
    const snap = await prisma.snap.findFirst({
      where: {
        id: snapId,
        senderId: userId,
      },
      include: {
        recipients: {
          include: {
            user: {
              select: {
                id: true,
                username: true,
                displayName: true,
                avatarUrl: true,
              },
            },
          },
        },
        screenshots: {
          include: {
            user: {
              select: {
                id: true,
                username: true,
                displayName: true,
              },
            },
          },
        },
      },
    });

    if (!snap) {
      throw new NotFoundError('Snap not found');
    }

    return snap;
  }

  // Update streak
  private async updateStreak(senderId: string, receiverId: string) {
    const existingStreak = await prisma.streak.findUnique({
      where: {
        senderId_receiverId: {
          senderId,
          receiverId,
        },
      },
    });

    const now = new Date();
    const expiresAt = dayjs().add(24, 'hours').toDate();

    if (existingStreak) {
      const hoursSinceLastInteraction = dayjs(now).diff(
        existingStreak.lastInteraction,
        'hour'
      );

      // Reset if more than 24 hours since last interaction
      const newCount = hoursSinceLastInteraction >= 24 ? 1 : existingStreak.count + 1;
      const longestStreak = Math.max(existingStreak.longestStreak, newCount);

      await prisma.streak.update({
        where: { id: existingStreak.id },
        data: {
          count: newCount,
          lastInteraction: now,
          expiresAt,
          isActive: true,
          longestStreak,
        },
      });
    } else {
      await prisma.streak.create({
        data: {
          senderId,
          receiverId,
          count: 1,
          lastInteraction: now,
          expiresAt,
          isActive: true,
          longestStreak: 1,
        },
      });
    }
  }

  // Get streaks for user
  async getStreaks(userId: string) {
    const streaks = await prisma.streak.findMany({
      where: {
        OR: [
          { senderId: userId },
          { receiverId: userId },
        ],
        isActive: true,
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true,
            displayName: true,
            avatarUrl: true,
          },
        },
        receiver: {
          select: {
            id: true,
            username: true,
            displayName: true,
            avatarUrl: true,
          },
        },
      },
      orderBy: { count: 'desc' },
    });

    // Group by friend and get highest streak
    const streakMap = new Map();
    for (const streak of streaks) {
      const friendId = streak.senderId === userId ? streak.receiverId : streak.senderId;
      const existing = streakMap.get(friendId);
      
      if (!existing || existing.count < streak.count) {
        streakMap.set(friendId, {
          ...streak,
          friend: streak.senderId === userId ? streak.receiver : streak.sender,
          hoursRemaining: Math.max(0, dayjs(streak.expiresAt).diff(dayjs(), 'hour')),
        });
      }
    }

    return Array.from(streakMap.values());
  }

  /**
   * Increment snap scores for sender and recipients (fire-and-forget)
   * Sender gets +1 for sending, each recipient gets +1 for receiving
   */
  private async incrementSnapScores(senderId: string, recipientIds: string[]): Promise<void> {
    try {
      // Increment sender's score by 1
      const senderUpdate = prisma.user.update({
        where: { id: senderId },
        data: { snapScore: { increment: 1 } },
      });

      // Increment each recipient's score by 1
      const recipientUpdates = recipientIds.map(id =>
        prisma.user.update({
          where: { id },
          data: { snapScore: { increment: 1 } },
        })
      );

      // Execute all updates in parallel
      await Promise.all([senderUpdate, ...recipientUpdates]);
    } catch (error) {
      // Fire-and-forget: log error but don't throw
      console.error('Failed to increment snap scores:', error);
    }
  }

  // Save a snap (toggle - if already saved, unsave)
  async saveSnap(userId: string, snapId: string) {
    // Check if snap exists and user has access
    const snap = await prisma.snap.findFirst({
      where: {
        id: snapId,
        OR: [
          { senderId: userId },
          { recipients: { some: { userId } } },
        ],
      },
    });

    if (!snap) {
      throw new NotFoundError('Snap not found or access denied');
    }

    // Check if already saved
    const existing = await prisma.savedSnap.findUnique({
      where: {
        userId_snapId: { userId, snapId },
      },
    });

    if (existing) {
      // Already saved - unsave it
      await prisma.savedSnap.delete({
        where: { id: existing.id },
      });
      return { saved: false, message: 'Snap unsaved' };
    }

    // Save the snap
    const savedSnap = await prisma.savedSnap.create({
      data: { userId, snapId },
    });

    return { saved: true, savedSnap, message: 'Snap saved' };
  }

  // Unsave a snap
  async unsaveSnap(userId: string, snapId: string) {
    const savedSnap = await prisma.savedSnap.findUnique({
      where: {
        userId_snapId: { userId, snapId },
      },
    });

    if (!savedSnap) {
      throw new NotFoundError('Saved snap not found');
    }

    await prisma.savedSnap.delete({
      where: { id: savedSnap.id },
    });

    return { success: true, message: 'Snap unsaved' };
  }

  // Get saved snaps with pagination
  async getSavedSnaps(userId: string, limit: number = 20, offset: number = 0) {
    const [savedSnaps, total] = await Promise.all([
      prisma.savedSnap.findMany({
        where: { userId },
        include: {
          snap: {
            include: {
              sender: {
                select: {
                  id: true,
                  username: true,
                  displayName: true,
                  avatarUrl: true,
                  avatarConfig: true,
                },
              },
            },
          },
        },
        orderBy: { savedAt: 'desc' },
        take: limit,
        skip: offset,
      }),
      prisma.savedSnap.count({ where: { userId } }),
    ]);

    return {
      savedSnaps,
      total,
      hasMore: offset + savedSnaps.length < total,
    };
  }

  // Check if snap is saved by user
  async isSnapSaved(userId: string, snapId: string) {
    const savedSnap = await prisma.savedSnap.findUnique({
      where: {
        userId_snapId: { userId, snapId },
      },
    });
    return { isSaved: !!savedSnap };
  }
}

export const snapService = new SnapService();
