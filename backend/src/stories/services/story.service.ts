import dayjs from 'dayjs';
import { prisma } from '../../index';
import { BadRequestError, NotFoundError, ForbiddenError } from '../../common/utils/AppError';
import { notificationService } from '../../notifications/services/notification.service';

export class StoryService {
  // Post a story
  async postStory(
    userId: string,
    data: {
      mediaUrl: string;
      mediaType: 'IMAGE' | 'VIDEO';
      thumbnailUrl?: string;
      duration?: number;
      caption?: string;
      drawingData?: any;
      stickers?: any;
      filters?: any;
      location?: string;
      latitude?: number;
      longitude?: number;
      privacy?: 'EVERYONE' | 'FRIENDS' | 'CLOSE_FRIENDS' | 'CUSTOM';
      allowReplies?: boolean;
      circleId?: string;
    }
  ) {
    const story = await prisma.story.create({
      data: {
        userId,
        mediaUrl: data.mediaUrl,
        mediaType: data.mediaType,
        thumbnailUrl: data.thumbnailUrl,
        duration: data.duration,
        caption: data.caption,
        drawingData: data.drawingData,
        stickers: data.stickers,
        filters: data.filters,
        location: data.location,
        latitude: data.latitude,
        longitude: data.longitude,
        privacy: data.privacy || 'FRIENDS',
        allowReplies: data.allowReplies !== false,
        circleId: data.circleId,
        expiresAt: dayjs().add(24, 'hours').toDate(),
      },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            displayName: true,
            avatarUrl: true,
            avatarConfig: true,
          },
        },
      },
    });

    return story;
  }

  // Get stories feed
  async getStoriesFeed(userId: string) {
    // Get friends
    const friendships = await prisma.friendship.findMany({
      where: { userId },
      select: { friendId: true, level: true },
    });

    const friendIds = friendships.map(f => f.friendId);
    const closeFriendIds = friendships
      .filter(f => f.level === 'CLOSE' || f.level === 'BEST')
      .map(f => f.friendId);

    // Get active stories from friends
    const stories = await prisma.story.findMany({
      where: {
        expiresAt: { gt: new Date() },
        OR: [
          // User's own stories
          { userId },
          // Friends' stories based on privacy
          {
            userId: { in: friendIds },
            OR: [
              { privacy: 'EVERYONE' },
              { privacy: 'FRIENDS' },
              {
                privacy: 'CLOSE_FRIENDS',
                userId: { in: closeFriendIds },
              },
            ],
          },
        ],
      },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            displayName: true,
            avatarUrl: true,
            avatarConfig: true,
            isVerified: true,
          },
        },
        views: {
          where: { userId },
          select: { viewedAt: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    // Group stories by user
    const storyMap = new Map<string, any[]>();
    for (const story of stories) {
      const userId = story.userId;
      if (!storyMap.has(userId)) {
        storyMap.set(userId, []);
      }
      storyMap.get(userId)!.push({
        ...story,
        hasViewed: story.views.length > 0,
      });
    }

    // Convert to array and sort by most recent unviewed
    const storyGroups = Array.from(storyMap.entries()).map(([userId, userStories]) => ({
      id: userStories[0].user.id,
      user: userStories[0].user,
      stories: userStories,
      hasUnviewed: userStories.some((s: any) => !s.hasViewed),
      lastStoryAt: userStories[0].createdAt,
    }));

    // Sort: own stories first, then unviewed, then by recency
    storyGroups.sort((a, b) => {
      if (a.user.id === userId) return -1;
      if (b.user.id === userId) return 1;
      if (a.hasUnviewed && !b.hasUnviewed) return -1;
      if (!a.hasUnviewed && b.hasUnviewed) return 1;
      return new Date(b.lastStoryAt).getTime() - new Date(a.lastStoryAt).getTime();
    });

    return storyGroups;
  }

  // Get user's stories
  async getUserStories(userId: string, viewerId?: string) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        username: true,
        displayName: true,
        avatarUrl: true,
        avatarConfig: true,
      },
    });

    if (!user) {
      throw new NotFoundError('User not found');
    }

    // Check friendship for privacy
    let canViewPrivate = userId === viewerId;
    let isCloseFriend = false;

    if (viewerId && userId !== viewerId) {
      const friendship = await prisma.friendship.findFirst({
        where: {
          userId: viewerId,
          friendId: userId,
        },
      });
      canViewPrivate = !!friendship;
      isCloseFriend = friendship?.level === 'CLOSE' || friendship?.level === 'BEST';
    }

    const stories = await prisma.story.findMany({
      where: {
        userId,
        expiresAt: { gt: new Date() },
        ...(userId !== viewerId && {
          OR: [
            { privacy: 'EVERYONE' },
            ...(canViewPrivate ? [{ privacy: 'FRIENDS' as const }] : []),
            ...(isCloseFriend ? [{ privacy: 'CLOSE_FRIENDS' as const }] : []),
          ],
        }),
      },
      include: {
        views: viewerId ? {
          where: { userId: viewerId },
          select: { viewedAt: true },
        } : false,
      },
      orderBy: { createdAt: 'asc' },
    });

    return {
      user,
      stories: stories.map(s => ({
        ...s,
        hasViewed: viewerId ? (s.views as any)?.length > 0 : false,
      })),
    };
  }

  // View a story
  async viewStory(viewerId: string, storyId: string) {
    const story = await prisma.story.findUnique({
      where: { id: storyId },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            displayName: true,
          },
        },
      },
    });

    if (!story) {
      throw new NotFoundError('Story not found');
    }

    if (story.expiresAt < new Date()) {
      throw new ForbiddenError('Story expired');
    }

    // Record view (upsert to avoid separate find + create)
    // Use createMany with skipDuplicates for a single atomic operation
    const created = await prisma.storyView.createMany({
      data: [{ storyId, userId: viewerId }],
      skipDuplicates: true,
    });

    if (created.count > 0) {
      // Only increment view count if this was a new view
      prisma.story.update({
        where: { id: storyId },
        data: { viewCount: { increment: 1 } },
      }).catch(() => {});
    }

    return story;
  }

  // Get story viewers
  async getStoryViewers(userId: string, storyId: string) {
    const story = await prisma.story.findFirst({
      where: {
        id: storyId,
        userId,
      },
    });

    if (!story) {
      throw new NotFoundError('Story not found');
    }

    const views = await prisma.storyView.findMany({
      where: { storyId },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            displayName: true,
            avatarUrl: true,
            avatarConfig: true,
          },
        },
      },
      orderBy: { viewedAt: 'desc' },
    });

    return views;
  }

  // React to story
  async reactToStory(userId: string, storyId: string, emoji: string) {
    const story = await prisma.story.findUnique({
      where: { id: storyId },
      include: {
        user: {
          select: {
            id: true,
            displayName: true,
          },
        },
      },
    });

    if (!story) {
      throw new NotFoundError('Story not found');
    }

    if (story.userId === userId) {
      throw new ForbiddenError('Cannot react to your own story');
    }

    if (story.expiresAt < new Date()) {
      throw new ForbiddenError('Story expired');
    }

    const reaction = await prisma.storyReaction.upsert({
      where: {
        storyId_userId: {
          storyId,
          userId,
        },
      },
      update: { emoji },
      create: {
        storyId,
        userId,
        emoji,
      },
    });

    // Notify story owner
    if (story.userId !== userId) {
      const reactor = await prisma.user.findUnique({
        where: { id: userId },
        select: { displayName: true },
      });

      await notificationService.sendPushNotification(story.userId, {
        type: 'STORY_REACTION',
        title: 'Story Reaction',
        body: `${reactor?.displayName} reacted ${emoji} to your story`,
        data: { storyId, userId },
      });
    }

    return reaction;
  }

  // Reply to story (creates a message)
  async replyToStory(userId: string, storyId: string, content: string) {
    const story = await prisma.story.findUnique({
      where: { id: storyId },
      include: {
        user: {
          select: {
            id: true,
            displayName: true,
          },
        },
      },
    });

    if (!story) {
      throw new NotFoundError('Story not found');
    }

    if (story.userId === userId) {
      throw new ForbiddenError('Cannot reply to your own story');
    }

    if (!story.allowReplies) {
      throw new ForbiddenError('Replies are disabled for this story');
    }

    // Find or create direct chat
    let chat = await prisma.chat.findFirst({
      where: {
        type: 'DIRECT',
        members: {
          every: {
            userId: { in: [userId, story.userId] },
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
              data: [
                { userId },
                { userId: story.userId },
              ],
            },
          },
        },
      });
    }

    // Create message with story reference
    const message = await prisma.message.create({
      data: {
        chatId: chat.id,
        senderId: userId,
        type: 'TEXT',
        content,
        storyReplyId: storyId,
      },
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
        storyReply: {
          select: {
            id: true,
            mediaUrl: true,
            mediaType: true,
            thumbnailUrl: true,
          },
        },
      },
    });

    // Notify story owner
    await notificationService.sendPushNotification(story.userId, {
      type: 'STORY_REPLY',
      title: 'Story Reply',
      body: `${message.sender.displayName} replied to your story`,
      data: { storyId, messageId: message.id, chatId: chat.id },
    });

    return { chat, message };
  }

  // Update story settings (privacy + allowReplies)
  async updateStorySettings(
    userId: string,
    storyId: string,
    data: { privacy?: 'EVERYONE' | 'FRIENDS' | 'CLOSE_FRIENDS' | 'CUSTOM'; allowReplies?: boolean }
  ) {
    const story = await prisma.story.findFirst({
      where: { id: storyId, userId },
    });

    if (!story) {
      throw new NotFoundError('Story not found');
    }

    const updated = await prisma.story.update({
      where: { id: storyId },
      data: {
        ...(data.privacy !== undefined && { privacy: data.privacy }),
        ...(data.allowReplies !== undefined && { allowReplies: data.allowReplies }),
      },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            displayName: true,
            avatarUrl: true,
            avatarConfig: true,
          },
        },
      },
    });

    return updated;
  }

  // Delete story
  async deleteStory(userId: string, storyId: string) {
    const story = await prisma.story.findFirst({
      where: {
        id: storyId,
        userId,
      },
    });

    if (!story) {
      throw new NotFoundError('Story not found');
    }

    await prisma.story.delete({
      where: { id: storyId },
    });

    return { success: true };
  }

  // Get my stories
  async getMyStories(userId: string) {
    const stories = await prisma.story.findMany({
      where: {
        userId,
        expiresAt: { gt: new Date() },
      },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            displayName: true,
            avatarUrl: true,
            avatarConfig: true,
            isVerified: true,
          },
        },
        _count: {
          select: { views: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return stories;
  }
}

export const storyService = new StoryService();
