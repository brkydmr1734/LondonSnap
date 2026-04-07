import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../../index';
import { BadRequestError, NotFoundError } from '../../common/utils/AppError';
import { authCache } from '../../common/utils/cache';

const updateProfileSchema = z.object({
  displayName: z.string().min(1).max(50).optional(),
  bio: z.string().max(150).optional(),
  birthday: z.string().optional(),
  gender: z.enum(['MALE', 'FEMALE', 'NON_BINARY', 'PREFER_NOT_TO_SAY']).optional(),
  course: z.string().max(100).optional(),
  graduationYear: z.number().min(2020).max(2035).optional(),
});

const privacySettingsSchema = z.object({
  whoCanMessage: z.enum(['EVERYONE', 'FRIENDS', 'CLOSE_FRIENDS', 'NOBODY']).optional(),
  whoCanViewStory: z.enum(['EVERYONE', 'FRIENDS', 'CLOSE_FRIENDS', 'NOBODY']).optional(),
  whoCanSeeLocation: z.enum(['EVERYONE', 'FRIENDS', 'CLOSE_FRIENDS', 'NOBODY']).optional(),
  whoCanFindMe: z.enum(['EVERYONE', 'FRIENDS', 'CLOSE_FRIENDS', 'NOBODY']).optional(),
  showInDiscover: z.boolean().optional(),
  showInNearby: z.boolean().optional(),
  showLastSeen: z.boolean().optional(),
  showReadReceipts: z.boolean().optional(),
  allowScreenshotNotify: z.boolean().optional(),
});

export class UserController {
  // Get profile
  async getProfile(req: Request, res: Response, next: NextFunction) {
    try {
      const userId = req.params.userId || req.user?.id;
      
      if (!userId) {
        throw new BadRequestError('User ID required');
      }
      
      const isOwnProfile = userId === req.user?.id;
      
      const user = await prisma.user.findUnique({
        where: { id: userId },
        select: {
          id: true,
          username: true,
          displayName: true,
          avatarUrl: true,
          avatarConfig: true,
          bio: true,
          isVerified: true,
          isUniversityStudent: true,
          snapScore: true,
          createdAt: true,
          university: {
            select: {
              id: true,
              name: true,
              shortName: true,
            },
          },
          course: true,
          graduationYear: true,
          // Only include sensitive info for own profile
          ...(isOwnProfile && {
            email: true,
            phone: true,
            birthday: true,
            gender: true,
            emailVerified: true,
            phoneVerified: true,
          }),
        },
      });
      
      if (!user) {
        throw new NotFoundError('User not found');
      }
      
      // Get friend count for target user
      const friendsCount = await prisma.friendship.count({ where: { userId } });
      
      // For own profile, return basic data
      if (isOwnProfile || !req.user) {
        res.json({
          success: true,
          data: {
            ...user,
            friendsCount,
            snapScore: user.snapScore,
          },
        });
        return;
      }
      
      // For viewing another user's profile, get additional social data
      const currentUserId = req.user.id;
      
      // Run parallel queries for efficiency
      const [
        friendship,
        pendingRequest,
        blockRecord,
        streak,
        mutualFriendsData,
        targetPrivacySettings,
      ] = await Promise.all([
        // Check if we're friends with target user
        prisma.friendship.findFirst({
          where: {
            userId: currentUserId,
            friendId: userId,
          },
        }),
        // Check if there's a pending friend request (either direction)
        prisma.friendRequest.findFirst({
          where: {
            OR: [
              { senderId: currentUserId, receiverId: userId, status: 'PENDING' },
              { senderId: userId, receiverId: currentUserId, status: 'PENDING' },
            ],
          },
        }),
        // Check if either user has blocked the other
        prisma.block.findFirst({
          where: {
            OR: [
              { blockerId: currentUserId, blockedId: userId },
              { blockerId: userId, blockedId: currentUserId },
            ],
          },
        }),
        // Get streak between users
        prisma.streak.findFirst({
          where: {
            OR: [
              { senderId: currentUserId, receiverId: userId },
              { senderId: userId, receiverId: currentUserId },
            ],
            isActive: true,
          },
        }),
        // Get mutual friends (users who are friends with both current user and target user)
        prisma.$queryRaw`
          SELECT u.id, u.username, u."displayName", u."avatarUrl"
          FROM "User" u
          INNER JOIN "Friendship" f1 ON f1."friendId" = u.id AND f1."userId" = ${userId}
          INNER JOIN "Friendship" f2 ON f2."friendId" = u.id AND f2."userId" = ${currentUserId}
          WHERE u.status = 'ACTIVE'
          LIMIT 10
        ` as Promise<Array<{ id: string; username: string; displayName: string; avatarUrl: string | null }>>,
        // Get target user's privacy settings
        prisma.userPrivacySettings.findUnique({
          where: { userId },
        }),
      ]);
      
      // Determine friendship status string
      let friendshipStatus: 'accepted' | 'pending' | 'blocked' | 'none' = 'none';
      if (blockRecord) {
        friendshipStatus = 'blocked';
      } else if (friendship) {
        friendshipStatus = 'accepted';
      } else if (pendingRequest) {
        friendshipStatus = 'pending';
      }
      
      // Derive isBestFriend and isCloseFriend from friendship level
      const isBestFriend = friendship?.level === 'BEST';
      const isCloseFriend = friendship?.level === 'CLOSE';
      
      // Check if blocked
      const isBlocked = !!blockRecord;
      
      // Get streak count
      const streakCount = streak?.count ?? 0;
      
      // Format mutual friends
      const mutualFriends = mutualFriendsData.map((friend) => ({
        id: friend.id,
        username: friend.username,
        displayName: friend.displayName,
        avatarUrl: friend.avatarUrl,
      }));
      
      // Get location with privacy check
      let location: { latitude: number; longitude: number; area: string | null; updatedAt: Date } | null = null;
      
      const privacyLevel = targetPrivacySettings?.whoCanSeeLocation ?? 'FRIENDS';
      let canSeeLocation = false;
      
      if (privacyLevel === 'EVERYONE') {
        canSeeLocation = true;
      } else if (privacyLevel === 'FRIENDS' && friendship) {
        canSeeLocation = true;
      } else if (privacyLevel === 'CLOSE_FRIENDS' && (friendship?.level === 'CLOSE' || friendship?.level === 'BEST')) {
        canSeeLocation = true;
      }
      // NOBODY means no one can see location
      
      if (canSeeLocation) {
        const userLocation = await prisma.userLocation.findFirst({
          where: { userId },
          orderBy: { updatedAt: 'desc' },
          select: {
            latitude: true,
            longitude: true,
            area: true,
            updatedAt: true,
          },
        });
        
        if (userLocation) {
          location = {
            latitude: userLocation.latitude,
            longitude: userLocation.longitude,
            area: userLocation.area,
            updatedAt: userLocation.updatedAt,
          };
        }
      }
      
      res.json({
        success: true,
        data: {
          id: user.id,
          username: user.username,
          displayName: user.displayName,
          avatarUrl: user.avatarUrl,
          avatarConfig: user.avatarConfig,
          bio: user.bio,
          isVerified: user.isVerified,
          snapScore: user.snapScore,
          friendsCount,
          streakCount,
          friendshipStatus,
          isBestFriend,
          isCloseFriend,
          isBlocked,
          mutualFriends,
          university: user.university,
          location,
        },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Update profile
  async updateProfile(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const data = updateProfileSchema.parse(req.body);
      
      const user = await prisma.user.update({
        where: { id: req.user.id },
        data: {
          ...data,
          birthday: data.birthday ? new Date(data.birthday) : undefined,
        },
        select: {
          id: true,
          username: true,
          displayName: true,
          avatarUrl: true,
          avatarConfig: true,
          bio: true,
          birthday: true,
          gender: true,
          course: true,
          graduationYear: true,
        },
      });
      
      // Invalidate auth cache so next request gets fresh user data
      authCache.delete(`user:${req.user.id}`);
      
      res.json({
        success: true,
        message: 'Profile updated',
        data: { user },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Update avatar
  async updateAvatar(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const { avatarUrl } = req.body;
      
      if (avatarUrl === undefined || avatarUrl === null) {
        throw new BadRequestError('Avatar URL required');
      }
      
      const user = await prisma.user.update({
        where: { id: req.user.id },
        data: { avatarUrl: avatarUrl || null },
        select: {
          id: true,
          avatarUrl: true,
        },
      });
      
      // Invalidate auth cache so next request gets fresh user data
      authCache.delete(`user:${req.user.id}`);
      
      res.json({
        success: true,
        message: 'Avatar updated',
        data: { user },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Update avatar config (Bitmoji-style)
  async updateAvatarConfig(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const { avatarConfig } = req.body;
      
      if (!avatarConfig || typeof avatarConfig !== 'string') {
        throw new BadRequestError('Avatar config string required');
      }
      
      const user = await prisma.user.update({
        where: { id: req.user.id },
        data: { avatarConfig },
        select: {
          id: true,
          avatarConfig: true,
        },
      });
      
      res.json({
        success: true,
        message: 'Avatar config updated',
        data: { user },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Get privacy settings
  async getPrivacySettings(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const settings = await prisma.userPrivacySettings.findUnique({
        where: { userId: req.user.id },
      });
      
      res.json({
        success: true,
        data: { settings },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Update privacy settings
  async updatePrivacySettings(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const data = privacySettingsSchema.parse(req.body);
      
      const settings = await prisma.userPrivacySettings.upsert({
        where: { userId: req.user.id },
        update: data,
        create: {
          userId: req.user.id,
          ...data,
        },
      });
      
      res.json({
        success: true,
        message: 'Privacy settings updated',
        data: { settings },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Get notification preferences
  async getNotificationPreferences(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const preferences = await prisma.notificationPreferences.findUnique({
        where: { userId: req.user.id },
      });
      
      res.json({
        success: true,
        data: { preferences },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Update notification preferences
  async updateNotificationPreferences(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const preferences = await prisma.notificationPreferences.upsert({
        where: { userId: req.user.id },
        update: req.body,
        create: {
          userId: req.user.id,
          ...req.body,
        },
      });
      
      res.json({
        success: true,
        message: 'Notification preferences updated',
        data: { preferences },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Search users
  async searchUsers(req: Request, res: Response, next: NextFunction) {
    try {
      const { q, limit = 20, offset = 0 } = req.query;
      
      if (!q || typeof q !== 'string' || q.length < 2) {
        throw new BadRequestError('Search query must be at least 2 characters');
      }
      
      const users = await prisma.user.findMany({
        where: {
          AND: [
            { status: 'ACTIVE' },
            { id: { not: req.user?.id } },
            {
              OR: [
                { username: { contains: q, mode: 'insensitive' } },
                { displayName: { contains: q, mode: 'insensitive' } },
              ],
            },
          ],
        },
        select: {
          id: true,
          username: true,
          displayName: true,
          avatarUrl: true,
          avatarConfig: true,
          isVerified: true,
          isUniversityStudent: true,
        },
        take: Number(limit),
        skip: Number(offset),
        orderBy: { displayName: 'asc' },
      });
      
      res.json({
        success: true,
        data: { users },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Get user by username
  async getUserByUsername(req: Request, res: Response, next: NextFunction) {
    try {
      const { username } = req.params;
      
      const user = await prisma.user.findUnique({
        where: { username: username.toLowerCase() },
        select: {
          id: true,
          username: true,
          displayName: true,
          avatarUrl: true,
          avatarConfig: true,
          bio: true,
          isVerified: true,
          isUniversityStudent: true,
          university: {
            select: {
              name: true,
              shortName: true,
            },
          },
        },
      });
      
      if (!user) {
        throw new NotFoundError('User not found');
      }
      
      res.json({
        success: true,
        data: { user },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Get sessions
  async getSessions(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const sessions = await prisma.session.findMany({
        where: { userId: req.user.id },
        select: {
          id: true,
          deviceType: true,
          deviceName: true,
          ipAddress: true,
          lastUsedAt: true,
          createdAt: true,
        },
        orderBy: { lastUsedAt: 'desc' },
      });
      
      // Mark current session
      const currentToken = req.token;
      const currentSession = await prisma.session.findUnique({
        where: { token: currentToken },
        select: { id: true },
      });
      
      const sessionsWithCurrent = sessions.map(s => ({
        ...s,
        isCurrent: s.id === currentSession?.id,
      }));
      
      res.json({
        success: true,
        data: { sessions: sessionsWithCurrent },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Revoke session
  async revokeSession(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const { sessionId } = req.params;
      
      await prisma.session.deleteMany({
        where: {
          id: sessionId,
          userId: req.user.id,
        },
      });
      
      res.json({
        success: true,
        message: 'Session revoked',
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Get interests
  async getInterests(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const interests = await prisma.userInterest.findMany({
        where: { userId: req.user.id },
      });
      
      res.json({
        success: true,
        data: { interests },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Update interests
  async updateInterests(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const { interests } = req.body;
      
      if (!Array.isArray(interests)) {
        throw new BadRequestError('Interests must be an array');
      }
      
      // Delete existing and create new
      await prisma.$transaction([
        prisma.userInterest.deleteMany({ where: { userId: req.user.id } }),
        prisma.userInterest.createMany({
          data: interests.map((i: { category: string; name: string }) => ({
            userId: req.user!.id,
            category: i.category as any,
            name: i.name,
          })),
        }),
      ]);
      
      const updatedInterests = await prisma.userInterest.findMany({
        where: { userId: req.user.id },
      });
      
      res.json({
        success: true,
        message: 'Interests updated',
        data: { interests: updatedInterests },
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Register device token
  async registerDeviceToken(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const { token, platform } = req.body;
      
      if (!token || !platform) {
        throw new BadRequestError('Token and platform are required');
      }
      
      await prisma.deviceToken.upsert({
        where: { token },
        update: {
          userId: req.user.id,
          platform,
          isActive: true,
          updatedAt: new Date(),
        },
        create: {
          userId: req.user.id,
          token,
          platform,
        },
      });
      
      res.json({
        success: true,
        message: 'Device token registered',
      });
    } catch (error) {
      next(error);
    }
  }
  
  // Remove device token
  async removeDeviceToken(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }
      
      const { token } = req.body;
      
      if (!token) {
        throw new BadRequestError('Token is required');
      }
      
      await prisma.deviceToken.deleteMany({
        where: {
          token,
          userId: req.user.id,
        },
      });
      
      res.json({
        success: true,
        message: 'Device token removed',
      });
    } catch (error) {
      next(error);
    }
  }

  // Update user location
  async updateLocation(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      const { latitude, longitude, accuracy } = req.body;
      if (typeof latitude !== 'number' || typeof longitude !== 'number') {
        throw new BadRequestError('latitude and longitude are required numbers');
      }

      // Determine London area from coordinates
      const area = UserController._detectLondonArea(latitude, longitude) as any;

      // Upsert: one location record per user (overwrite old)
      const location = await prisma.userLocation.upsert({
        where: { id: await prisma.userLocation.findFirst({ where: { userId: req.user.id }, select: { id: true } }).then(l => l?.id ?? 'none') },
        update: { latitude, longitude, area, accuracy: accuracy ?? null, updatedAt: new Date() },
        create: { userId: req.user.id, latitude, longitude, area, accuracy: accuracy ?? null },
      });

      res.json({ success: true, data: { location } });
    } catch (error) {
      next(error);
    }
  }

  // Get friends with their locations (privacy-filtered)
  async getFriendLocations(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      // Get all friendships with level
      const friendships = await prisma.friendship.findMany({
        where: { userId: req.user.id },
        select: { friendId: true, level: true },
      });

      if (friendships.length === 0) {
        return res.json({ success: true, data: { users: [] } });
      }

      const friendIds = friendships.map(f => f.friendId);
      const closeFriendIds = friendships
        .filter(f => f.level === 'CLOSE' || f.level === 'BEST')
        .map(f => f.friendId);

      // Get friends with privacy settings and latest location
      const friends = await prisma.user.findMany({
        where: {
          id: { in: friendIds },
          status: 'ACTIVE',
        },
        select: {
          id: true,
          username: true,
          displayName: true,
          avatarUrl: true,
          avatarConfig: true,
          isOnline: true,
          lastSeenAt: true,
          privacySettings: {
            select: { whoCanSeeLocation: true },
          },
          locations: {
            orderBy: { updatedAt: 'desc' },
            take: 1,
            select: { latitude: true, longitude: true, area: true, updatedAt: true },
          },
        },
      });

      // Filter by privacy
      const visibleFriends = friends.filter(friend => {
        const privacy = friend.privacySettings?.whoCanSeeLocation ?? 'FRIENDS';
        if (privacy === 'NOBODY') return false;
        if (privacy === 'EVERYONE') return true;
        if (privacy === 'FRIENDS') return true; // We're already friends
        if (privacy === 'CLOSE_FRIENDS') return closeFriendIds.includes(friend.id);
        return false;
      }).filter(friend => friend.locations.length > 0) // Must have location data
      .map(friend => {
        const loc = friend.locations[0];
        return {
          id: friend.id,
          username: friend.username,
          displayName: friend.displayName,
          avatarUrl: friend.avatarUrl,
          avatarConfig: friend.avatarConfig,
          isOnline: friend.isOnline,
          lastSeenAt: friend.lastSeenAt,
          latitude: loc.latitude,
          longitude: loc.longitude,
          area: loc.area,
          locationUpdatedAt: loc.updatedAt,
        };
      });

      res.json({ success: true, data: { users: visibleFriends } });
    } catch (error) {
      next(error);
    }
  }

  // Simple London area detection from lat/lng
  private static _detectLondonArea(lat: number, lng: number): string | null {
    const areas: { name: string; lat: number; lng: number; radius: number }[] = [
      { name: 'SOHO', lat: 51.5137, lng: -0.1360, radius: 0.008 },
      { name: 'CAMDEN', lat: 51.5390, lng: -0.1426, radius: 0.012 },
      { name: 'SHOREDITCH', lat: 51.5265, lng: -0.0780, radius: 0.010 },
      { name: 'BRIXTON', lat: 51.4613, lng: -0.1156, radius: 0.012 },
      { name: 'HACKNEY', lat: 51.5450, lng: -0.0553, radius: 0.015 },
      { name: 'KENSINGTON', lat: 51.4990, lng: -0.1938, radius: 0.015 },
      { name: 'WESTMINSTER', lat: 51.4975, lng: -0.1357, radius: 0.012 },
      { name: 'ISLINGTON', lat: 51.5362, lng: -0.1033, radius: 0.012 },
      { name: 'GREENWICH', lat: 51.4769, lng: -0.0005, radius: 0.015 },
      { name: 'STRATFORD', lat: 51.5430, lng: -0.0003, radius: 0.012 },
      { name: 'KINGS_CROSS', lat: 51.5317, lng: -0.1240, radius: 0.008 },
      { name: 'NOTTING_HILL', lat: 51.5095, lng: -0.1965, radius: 0.010 },
      { name: 'FULHAM', lat: 51.4730, lng: -0.2030, radius: 0.015 },
      { name: 'WIMBLEDON', lat: 51.4215, lng: -0.2070, radius: 0.015 },
    ];
    for (const a of areas) {
      const d = Math.sqrt(Math.pow(lat - a.lat, 2) + Math.pow(lng - a.lng, 2));
      if (d <= a.radius) return a.name;
    }
    return 'OTHER';
  }
}

export const userController = new UserController();
