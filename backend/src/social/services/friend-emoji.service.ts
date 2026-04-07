import dayjs from 'dayjs';
import { prisma } from '../../index';
import { dataCache } from '../../common/utils/cache';

export interface FriendEmoji {
  emoji: string;
  label: string;
}

// Emoji priority (lower = higher priority)
const EMOJI_PRIORITY = {
  '💛': 1,  // #1 Best Friend
  '❤️': 0,   // BFF (2+ consecutive weeks) - highest priority
  '💕': -1,  // Super BFF (2+ consecutive months) - highest priority
  '😊': 2,  // Best Friends (top 8)
  '🔥': 3,  // Snap Streak
  '⏳': 3,  // Streak expiring (same priority as streak)
  '👶': 4,  // New friend
};

export class FriendEmojiService {
  private readonly CACHE_TTL_MS = 300_000; // 5 minutes

  /**
   * Get friend emojis for a user (with caching)
   */
  async getFriendEmojis(userId: string): Promise<Map<string, FriendEmoji>> {
    const cacheKey = `friendEmojis:${userId}`;
    let emojis = dataCache.get<Map<string, FriendEmoji>>(cacheKey);
    
    if (!emojis) {
      emojis = await this.calculateFriendEmojis(userId);
      dataCache.set(cacheKey, emojis, this.CACHE_TTL_MS);
    }
    
    return emojis;
  }

  /**
   * Get emoji for a specific friend
   */
  async getFriendEmoji(userId: string, friendId: string): Promise<FriendEmoji | null> {
    const emojis = await this.getFriendEmojis(userId);
    return emojis.get(friendId) || null;
  }

  /**
   * Calculate all friend emojis for a user
   */
  private async calculateFriendEmojis(userId: string): Promise<Map<string, FriendEmoji>> {
    const emojiMap = new Map<string, FriendEmoji>();
    const sevenDaysAgo = dayjs().subtract(7, 'days').toDate();
    const now = new Date();

    // Get all friendships for the user
    const friendships = await prisma.friendship.findMany({
      where: { userId },
      select: { friendId: true, createdAt: true },
    });

    if (friendships.length === 0) {
      return emojiMap;
    }

    const friendIds = friendships.map(f => f.friendId);

    // Run queries in parallel for performance
    const [snapCounts, streaks] = await Promise.all([
      this.getSnapCountsBetweenUsers(userId, friendIds, sevenDaysAgo),
      this.getActiveStreaks(userId, friendIds),
    ]);

    // Sort friends by total snap exchange count (descending)
    const sortedFriends = Array.from(snapCounts.entries())
      .sort((a, b) => b[1] - a[1]);

    // Determine #1 Best Friend (💛)
    if (sortedFriends.length > 0 && sortedFriends[0][1] > 0) {
      const bestFriendId = sortedFriends[0][0];
      emojiMap.set(bestFriendId, { emoji: '💛', label: '#1 Best Friend' });
    }

    // Determine Best Friends (😊) - top 8 by snap exchange (excluding #1)
    const top8 = sortedFriends.slice(1, 9);
    for (const [friendId, count] of top8) {
      if (count > 0 && !emojiMap.has(friendId)) {
        emojiMap.set(friendId, { emoji: '😊', label: 'Best Friends' });
      }
    }

    // Check streaks (🔥 or ⏳)
    for (const streak of streaks) {
      const friendId = streak.senderId === userId ? streak.receiverId : streak.senderId;
      const hoursRemaining = dayjs(streak.expiresAt).diff(now, 'hour');
      
      // Only add streak emoji if no higher priority emoji exists
      if (!emojiMap.has(friendId) || EMOJI_PRIORITY['🔥'] < EMOJI_PRIORITY[emojiMap.get(friendId)!.emoji as keyof typeof EMOJI_PRIORITY]) {
        if (hoursRemaining <= 4) {
          emojiMap.set(friendId, { emoji: '⏳', label: 'Streak expiring soon!' });
        } else {
          emojiMap.set(friendId, { emoji: '🔥', label: 'Snap Streak' });
        }
      } else if (emojiMap.has(friendId)) {
        // If friend has another emoji but also has an expiring streak, we might want to warn
        // For now, keep the higher priority emoji but we could add secondary emojis later
        if (hoursRemaining <= 4) {
          // Could add warning indicator in future
        }
      }
    }

    // Check for new friends (👶) - friendship created within last 7 days
    for (const friendship of friendships) {
      if (!emojiMap.has(friendship.friendId)) {
        const friendshipAge = dayjs(now).diff(friendship.createdAt, 'day');
        if (friendshipAge <= 7) {
          emojiMap.set(friendship.friendId, { emoji: '👶', label: 'New friend' });
        }
      }
    }

    return emojiMap;
  }

  /**
   * Get snap counts between user and their friends in the last 7 days
   * Returns a map of friendId -> total snaps exchanged
   */
  private async getSnapCountsBetweenUsers(
    userId: string,
    friendIds: string[],
    since: Date
  ): Promise<Map<string, number>> {
    const countMap = new Map<string, number>();

    // Initialize all friends with 0
    for (const friendId of friendIds) {
      countMap.set(friendId, 0);
    }

    // Count snaps sent by user to friends
    const sentSnaps = await prisma.snapRecipient.groupBy({
      by: ['userId'],
      where: {
        userId: { in: friendIds },
        snap: {
          senderId: userId,
          createdAt: { gte: since },
        },
      },
      _count: true,
    });

    for (const snap of sentSnaps) {
      const current = countMap.get(snap.userId) || 0;
      countMap.set(snap.userId, current + snap._count);
    }

    // Count snaps received by user from friends
    const receivedSnaps = await prisma.snap.groupBy({
      by: ['senderId'],
      where: {
        senderId: { in: friendIds },
        createdAt: { gte: since },
        recipients: {
          some: { userId },
        },
      },
      _count: true,
    });

    for (const snap of receivedSnaps) {
      const current = countMap.get(snap.senderId) || 0;
      countMap.set(snap.senderId, current + snap._count);
    }

    return countMap;
  }

  /**
   * Get active streaks for user with specified friends
   */
  private async getActiveStreaks(userId: string, friendIds: string[]) {
    return prisma.streak.findMany({
      where: {
        isActive: true,
        OR: [
          { senderId: userId, receiverId: { in: friendIds } },
          { senderId: { in: friendIds }, receiverId: userId },
        ],
      },
      select: {
        senderId: true,
        receiverId: true,
        count: true,
        expiresAt: true,
      },
    });
  }

  /**
   * Invalidate cache for a user (call when snap sent/received)
   */
  invalidateCache(userId: string): void {
    dataCache.delete(`friendEmojis:${userId}`);
  }
}

export const friendEmojiService = new FriendEmojiService();
