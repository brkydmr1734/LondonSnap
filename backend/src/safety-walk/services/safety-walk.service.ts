import { prisma } from '../../index';
import { logger } from '../../common/utils/logger';
import { notificationService } from '../../notifications/services/notification.service';
import { BadRequestError, NotFoundError, ForbiddenError } from '../../common/utils/AppError';
import { SafetyWalkStatus, FriendshipLevel, ReportReason, ReportStatus, ChatType } from '@prisma/client';

interface RouteData {
  startLat: number;
  startLng: number;
  endLat: number;
  endLng: number;
  routePolyline?: any;
  estimatedDuration?: number;
  transportMode?: string;
}

interface CompanionCandidate {
  id: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  avatarConfig: string | null;
  universityId: string | null;
  safetyScore: number;
  distance: number;
  friendshipLevel: FriendshipLevel | 'SAME_UNIVERSITY';
  universityName?: string;
}

export class SafetyWalkService {
  /**
   * Haversine formula to calculate distance between two points in meters
   */
  private calculateDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R = 6371000; // Earth's radius in meters
    const toRad = (deg: number) => (deg * Math.PI) / 180;

    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
    const c = 2 * Math.asin(Math.sqrt(a));

    return R * c;
  }

  /**
   * Find potential companions for a Safety Walk
   */
  async findCompanions(
    userId: string,
    startLat: number,
    startLng: number,
    endLat: number,
    endLng: number,
    radius: number = 2000
  ): Promise<CompanionCandidate[]> {
    // Get user info
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { universityId: true },
    });

    // Get friends with their friendship levels
    const friendships = await prisma.friendship.findMany({
      where: { userId },
      select: { friendId: true, level: true },
    });
    const friendMap = new Map(friendships.map((f) => [f.friendId, f.level]));
    const friendIds = Array.from(friendMap.keys());

    // Get users from same university (if applicable)
    let universityUsers: string[] = [];
    if (user?.universityId) {
      const sameUniUsers = await prisma.user.findMany({
        where: {
          universityId: user.universityId,
          id: { notIn: [userId, ...friendIds] },
          status: 'ACTIVE',
        },
        select: { id: true },
      });
      universityUsers = sameUniUsers.map((u) => u.id);
    }

    // Combine candidate pools
    const candidateIds = [...new Set([...friendIds, ...universityUsers])];
    if (candidateIds.length === 0) return [];

    // Get candidates with their latest locations
    const candidates = await prisma.user.findMany({
      where: {
        id: { in: candidateIds },
        isOnline: true,
        status: 'ACTIVE',
        privacySettings: {
          OR: [{ whoCanSeeLocation: 'EVERYONE' }, { whoCanSeeLocation: 'FRIENDS' }],
        },
      },
      select: {
        id: true,
        username: true,
        displayName: true,
        avatarUrl: true,
        avatarConfig: true,
        universityId: true,
        university: { select: { name: true } },
        locations: {
          orderBy: { updatedAt: 'desc' },
          take: 1,
        },
        privacySettings: { select: { whoCanSeeLocation: true } },
      },
    });

    // Filter by location and privacy
    const filteredCandidates: CompanionCandidate[] = [];

    for (const candidate of candidates) {
      // Check privacy for non-friends
      const isFriend = friendMap.has(candidate.id);
      if (!isFriend && candidate.privacySettings?.whoCanSeeLocation !== 'EVERYONE') {
        continue;
      }

      // Check location proximity
      const location = candidate.locations[0];
      if (!location) continue;

      const distanceToStart = this.calculateDistance(
        startLat,
        startLng,
        location.latitude,
        location.longitude
      );
      const distanceToEnd = this.calculateDistance(
        endLat,
        endLng,
        location.latitude,
        location.longitude
      );
      const minDistance = Math.min(distanceToStart, distanceToEnd);

      if (minDistance > radius) continue;

      // Get or create safety score
      let safetyScore = await prisma.safetyScore.findUnique({
        where: { userId: candidate.id },
      });

      if (!safetyScore) {
        safetyScore = await prisma.safetyScore.create({
          data: { userId: candidate.id },
        });
      }

      // Filter by safety score threshold
      if (safetyScore.score < 60) continue;

      filteredCandidates.push({
        id: candidate.id,
        username: candidate.username,
        displayName: candidate.displayName,
        avatarUrl: candidate.avatarUrl,
        avatarConfig: candidate.avatarConfig,
        universityId: candidate.universityId,
        safetyScore: safetyScore.score,
        distance: minDistance,
        friendshipLevel: isFriend ? friendMap.get(candidate.id)! : 'SAME_UNIVERSITY',
        universityName: candidate.university?.name,
      });
    }

    // Sort: friendship level > safety score > proximity
    const levelPriority: Record<string, number> = {
      BEST: 4,
      CLOSE: 3,
      NORMAL: 2,
      SAME_UNIVERSITY: 1,
    };

    filteredCandidates.sort((a, b) => {
      const levelDiff = levelPriority[b.friendshipLevel] - levelPriority[a.friendshipLevel];
      if (levelDiff !== 0) return levelDiff;

      const scoreDiff = b.safetyScore - a.safetyScore;
      if (scoreDiff !== 0) return scoreDiff;

      return a.distance - b.distance;
    });

    return filteredCandidates;
  }

  /**
   * Create a new walk request
   */
  async createWalkRequest(
    requesterId: string,
    companionId: string,
    routeData: RouteData
  ) {
    // Validate users exist and are active
    const [requester, companion] = await Promise.all([
      prisma.user.findUnique({ where: { id: requesterId }, select: { id: true, displayName: true, status: true } }),
      prisma.user.findUnique({ where: { id: companionId }, select: { id: true, status: true } }),
    ]);

    if (!requester || requester.status !== 'ACTIVE') {
      throw new BadRequestError('Requester not found or inactive');
    }
    if (!companion || companion.status !== 'ACTIVE') {
      throw new BadRequestError('Companion not found or inactive');
    }

    // Check for existing active walk
    const existingWalk = await prisma.safetyWalk.findFirst({
      where: {
        OR: [{ requesterId }, { companionId: requesterId }],
        status: { in: ['PENDING', 'ACCEPTED', 'ACTIVE'] },
      },
    });

    if (existingWalk) {
      throw new BadRequestError('You already have an active walk');
    }

    // Create ephemeral chat for the walk
    const chat = await prisma.chat.create({
      data: {
        type: ChatType.SAFETY_WALK,
        isDisappearing: true,
        disappearAfter: 3600,
        members: {
          createMany: {
            data: [{ userId: requesterId }, { userId: companionId }],
          },
        },
      },
    });

    // Create the walk request
    const walk = await prisma.safetyWalk.create({
      data: {
        requesterId,
        companionId,
        status: SafetyWalkStatus.PENDING,
        startLat: routeData.startLat,
        startLng: routeData.startLng,
        endLat: routeData.endLat,
        endLng: routeData.endLng,
        routePolyline: routeData.routePolyline,
        estimatedDuration: routeData.estimatedDuration,
        transportMode: routeData.transportMode || 'WALKING',
        chatId: chat.id,
      },
      include: {
        requester: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        companion: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        chat: true,
      },
    });

    // Send push notification
    await notificationService.sendPushNotification(companionId, {
      type: 'SAFETY_WALK_INVITE',
      title: 'Safety Walk Request',
      body: `${requester.displayName} wants to walk with you`,
      data: { walkId: walk.id },
    });

    logger.info(`Safety walk request created: ${walk.id}`);
    return walk;
  }

  /**
   * Accept a walk request
   */
  async acceptWalk(walkId: string, companionId: string) {
    const walk = await prisma.safetyWalk.findUnique({
      where: { id: walkId },
      include: { companion: { select: { displayName: true } } },
    });

    if (!walk) throw new NotFoundError('Walk not found');
    if (walk.status !== SafetyWalkStatus.PENDING) {
      throw new BadRequestError('Walk is not pending');
    }
    if (walk.companionId !== companionId) {
      throw new ForbiddenError('You are not the companion for this walk');
    }

    const updatedWalk = await prisma.safetyWalk.update({
      where: { id: walkId },
      data: { status: SafetyWalkStatus.ACCEPTED },
      include: {
        requester: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        companion: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        chat: true,
      },
    });

    // Notify requester
    await notificationService.sendPushNotification(walk.requesterId, {
      type: 'COMPANION_ARRIVED',
      title: 'Walk Accepted!',
      body: `${walk.companion.displayName} accepted your walk request!`,
      data: { walkId },
    });

    logger.info(`Safety walk accepted: ${walkId}`);
    return updatedWalk;
  }

  /**
   * Decline a walk request
   */
  async declineWalk(walkId: string, companionId: string) {
    const walk = await prisma.safetyWalk.findUnique({
      where: { id: walkId },
    });

    if (!walk) throw new NotFoundError('Walk not found');
    if (walk.status !== SafetyWalkStatus.PENDING) {
      throw new BadRequestError('Walk is not pending');
    }
    if (walk.companionId !== companionId) {
      throw new ForbiddenError('You are not the companion for this walk');
    }

    const updatedWalk = await prisma.safetyWalk.update({
      where: { id: walkId },
      data: { status: SafetyWalkStatus.CANCELLED },
      include: {
        requester: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        companion: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
      },
    });

    // Notify requester
    await notificationService.sendPushNotification(walk.requesterId, {
      type: 'SYSTEM',
      title: 'Walk Declined',
      body: 'Your walk request was declined',
      data: { walkId },
    });

    logger.info(`Safety walk declined: ${walkId}`);
    return updatedWalk;
  }

  /**
   * Start a walk (after companion arrives)
   */
  async startWalk(walkId: string, userId: string) {
    const walk = await prisma.safetyWalk.findUnique({
      where: { id: walkId },
      include: {
        requester: { select: { displayName: true } },
        companion: { select: { displayName: true } },
      },
    });

    if (!walk) throw new NotFoundError('Walk not found');
    if (walk.status !== SafetyWalkStatus.ACCEPTED) {
      throw new BadRequestError('Walk is not ready to start');
    }
    if (walk.requesterId !== userId && walk.companionId !== userId) {
      throw new ForbiddenError('You are not a participant of this walk');
    }

    const updatedWalk = await prisma.safetyWalk.update({
      where: { id: walkId },
      data: {
        status: SafetyWalkStatus.ACTIVE,
        startedAt: new Date(),
      },
      include: {
        requester: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        companion: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        chat: true,
      },
    });

    // Notify both users
    await Promise.all([
      notificationService.sendPushNotification(walk.requesterId, {
        type: 'COMPANION_ARRIVED',
        title: 'Walk Started',
        body: 'Your Safety Walk has started. Stay safe!',
        data: { walkId },
      }),
      notificationService.sendPushNotification(walk.companionId, {
        type: 'COMPANION_ARRIVED',
        title: 'Walk Started',
        body: 'Your Safety Walk has started. Stay safe!',
        data: { walkId },
      }),
    ]);

    logger.info(`Safety walk started: ${walkId}`);
    return updatedWalk;
  }

  /**
   * Update location during walk
   */
  async updateLocation(
    walkId: string,
    userId: string,
    lat: number,
    lng: number,
    accuracy?: number,
    speed?: number,
    heading?: number
  ) {
    const walk = await prisma.safetyWalk.findUnique({
      where: { id: walkId },
    });

    if (!walk) throw new NotFoundError('Walk not found');
    if (walk.status !== SafetyWalkStatus.ACTIVE) {
      throw new BadRequestError('Walk is not active');
    }
    if (walk.requesterId !== userId && walk.companionId !== userId) {
      throw new ForbiddenError('You are not a participant of this walk');
    }

    // Create location record
    await prisma.safetyWalkLocation.create({
      data: {
        walkId,
        userId,
        latitude: lat,
        longitude: lng,
        accuracy,
        speed,
        heading,
      },
    });

    // Get companion's latest location
    const companionId = walk.requesterId === userId ? walk.companionId : walk.requesterId;
    const companionLocation = await prisma.safetyWalkLocation.findFirst({
      where: { walkId, userId: companionId },
      orderBy: { timestamp: 'desc' },
    });

    let companionDistance: number | null = null;

    if (companionLocation) {
      companionDistance = this.calculateDistance(
        lat,
        lng,
        companionLocation.latitude,
        companionLocation.longitude
      );

      // Check proximity thresholds
      if (companionDistance > 500) {
        // Critical alert
        await Promise.all([
          notificationService.sendPushNotification(walk.requesterId, {
            type: 'SOS_ALERT',
            title: 'Critical: Companion Too Far',
            body: 'Your companion is more than 500m away!',
            data: { walkId, distance: companionDistance.toString() },
          }),
          notificationService.sendPushNotification(walk.companionId, {
            type: 'SOS_ALERT',
            title: 'Critical: Companion Too Far',
            body: 'Your companion is more than 500m away!',
            data: { walkId, distance: companionDistance.toString() },
          }),
        ]);
      } else if (companionDistance > 200) {
        // Warning
        await Promise.all([
          notificationService.sendPushNotification(walk.requesterId, {
            type: 'SYSTEM',
            title: 'Warning: Companion Distance',
            body: 'Your companion is getting far. Stay closer!',
            data: { walkId, distance: companionDistance.toString() },
          }),
          notificationService.sendPushNotification(walk.companionId, {
            type: 'SYSTEM',
            title: 'Warning: Companion Distance',
            body: 'Your companion is getting far. Stay closer!',
            data: { walkId, distance: companionDistance.toString() },
          }),
        ]);
      }
    }

    return { success: true, companionDistance };
  }

  /**
   * Trigger SOS emergency
   */
  async triggerSOS(walkId: string, userId: string) {
    const walk = await prisma.safetyWalk.findUnique({
      where: { id: walkId },
      include: {
        requester: { select: { id: true, displayName: true } },
        companion: { select: { id: true, displayName: true } },
      },
    });

    if (!walk) throw new NotFoundError('Walk not found');
    if (walk.status !== SafetyWalkStatus.ACTIVE) {
      throw new BadRequestError('Walk is not active');
    }
    if (walk.requesterId !== userId && walk.companionId !== userId) {
      throw new ForbiddenError('You are not a participant of this walk');
    }

    // Update walk with SOS status
    await prisma.safetyWalk.update({
      where: { id: walkId },
      data: {
        sosTriggered: true,
        sosTriggeredAt: new Date(),
        sosTriggeredBy: userId,
        status: SafetyWalkStatus.SOS_TRIGGERED,
      },
    });

    const userName = walk.requesterId === userId
      ? walk.requester.displayName
      : walk.companion.displayName;
    const companionId = walk.requesterId === userId ? walk.companionId : walk.requesterId;

    // Get user's close/best friends (top 5)
    const closeFriends = await prisma.friendship.findMany({
      where: {
        userId,
        level: { in: ['CLOSE', 'BEST'] },
      },
      include: {
        friend: { select: { id: true } },
      },
      take: 5,
    });

    // Send notifications to companion
    await notificationService.sendPushNotification(companionId, {
      type: 'SOS_ALERT',
      title: 'SOS! Emergency Alert',
      body: `${userName} needs help!`,
      data: { walkId, emergency: 'true' },
    });

    // Send notifications to close friends
    const friendNotifications = closeFriends.map((f) =>
      notificationService.sendPushNotification(f.friend.id, {
        type: 'SOS_ALERT',
        title: 'SOS Alert!',
        body: `${userName} triggered an emergency during a Safety Walk`,
        data: { walkId, emergency: 'true' },
      })
    );
    await Promise.all(friendNotifications);

    // Create a report record
    await prisma.report.create({
      data: {
        authorId: userId,
        reportedUserId: null,
        reason: ReportReason.VIOLENCE,
        description: `SOS triggered during Safety Walk ${walkId}`,
        status: ReportStatus.PENDING,
      },
    });

    // Get companion's latest location
    const companionLocation = await prisma.safetyWalkLocation.findFirst({
      where: { walkId, userId: companionId },
      orderBy: { timestamp: 'desc' },
    });

    logger.warn(`SOS triggered for walk ${walkId} by user ${userId}`);

    return {
      emergency: true,
      companionLocation: companionLocation
        ? { lat: companionLocation.latitude, lng: companionLocation.longitude }
        : null,
      emergencyContacts: closeFriends.length,
    };
  }

  /**
   * Complete a walk
   */
  async completeWalk(walkId: string, userId: string) {
    const walk = await prisma.safetyWalk.findUnique({
      where: { id: walkId },
    });

    if (!walk) throw new NotFoundError('Walk not found');
    if (walk.status !== SafetyWalkStatus.ACTIVE) {
      throw new BadRequestError('Walk is not active');
    }
    if (walk.requesterId !== userId && walk.companionId !== userId) {
      throw new ForbiddenError('You are not a participant of this walk');
    }

    const endedAt = new Date();
    const duration = walk.startedAt
      ? Math.floor((endedAt.getTime() - walk.startedAt.getTime()) / 1000)
      : 0;

    // Calculate total distance from location updates
    const locations = await prisma.safetyWalkLocation.findMany({
      where: { walkId, userId: walk.requesterId },
      orderBy: { timestamp: 'asc' },
    });

    let totalDistance = 0;
    for (let i = 1; i < locations.length; i++) {
      totalDistance += this.calculateDistance(
        locations[i - 1].latitude,
        locations[i - 1].longitude,
        locations[i].latitude,
        locations[i].longitude
      );
    }

    const updatedWalk = await prisma.safetyWalk.update({
      where: { id: walkId },
      data: {
        status: SafetyWalkStatus.COMPLETED,
        endedAt,
      },
      include: {
        requester: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        companion: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
      },
    });

    // Update SafetyScores for both users
    await Promise.all([
      this.incrementSafetyScoreWalks(walk.requesterId, true),
      this.incrementSafetyScoreWalks(walk.companionId, true),
    ]);

    // Notify both users
    await Promise.all([
      notificationService.sendPushNotification(walk.requesterId, {
        type: 'WALK_COMPLETED',
        title: 'Walk Completed',
        body: 'Great job! Your Safety Walk is complete.',
        data: { walkId },
      }),
      notificationService.sendPushNotification(walk.companionId, {
        type: 'WALK_COMPLETED',
        title: 'Walk Completed',
        body: 'Great job! Your Safety Walk is complete.',
        data: { walkId },
      }),
    ]);

    logger.info(`Safety walk completed: ${walkId}`);
    return { walk: updatedWalk, stats: { duration, distance: totalDistance } };
  }

  /**
   * Cancel a walk
   */
  async cancelWalk(walkId: string, userId: string) {
    const walk = await prisma.safetyWalk.findUnique({
      where: { id: walkId },
    });

    if (!walk) throw new NotFoundError('Walk not found');
    if (walk.requesterId !== userId && walk.companionId !== userId) {
      throw new ForbiddenError('You are not a participant of this walk');
    }

    // Check for late cancellation (after walk started and less than 5 min)
    const isLateCancellation =
      walk.status === SafetyWalkStatus.ACTIVE &&
      walk.startedAt &&
      Date.now() - walk.startedAt.getTime() < 5 * 60 * 1000;

    const updatedWalk = await prisma.safetyWalk.update({
      where: { id: walkId },
      data: {
        status: SafetyWalkStatus.CANCELLED,
        endedAt: new Date(),
      },
      include: {
        requester: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        companion: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
      },
    });

    // Apply late cancellation penalty
    if (isLateCancellation) {
      await this.incrementSafetyScoreWalks(userId, false, true);
    }

    // Notify companion
    const companionId = walk.requesterId === userId ? walk.companionId : walk.requesterId;
    await notificationService.sendPushNotification(companionId, {
      type: 'SYSTEM',
      title: 'Walk Cancelled',
      body: 'The Safety Walk has been cancelled',
      data: { walkId },
    });

    logger.info(`Safety walk cancelled: ${walkId}`);
    return updatedWalk;
  }

  /**
   * Rate companion after walk
   */
  async rateCompanion(
    walkId: string,
    raterId: string,
    ratedId: string,
    score: number,
    comment?: string
  ) {
    if (score < 1 || score > 5) {
      throw new BadRequestError('Score must be between 1 and 5');
    }

    const walk = await prisma.safetyWalk.findUnique({
      where: { id: walkId },
    });

    if (!walk) throw new NotFoundError('Walk not found');
    if (walk.status !== SafetyWalkStatus.COMPLETED) {
      throw new BadRequestError('Walk is not completed');
    }
    if (walk.requesterId !== raterId && walk.companionId !== raterId) {
      throw new ForbiddenError('You are not a participant of this walk');
    }

    // Verify ratedId is the other participant
    const expectedRatedId = walk.requesterId === raterId ? walk.companionId : walk.requesterId;
    if (ratedId !== expectedRatedId) {
      throw new BadRequestError('Invalid rated user');
    }

    // Upsert rating
    const rating = await prisma.safetyWalkRating.upsert({
      where: { walkId_raterId: { walkId, raterId } },
      update: { score, comment },
      create: { walkId, raterId, ratedId, score, comment },
    });

    // Recalculate safety score
    await this.recalculateSafetyScore(ratedId);

    logger.info(`Safety walk rating created: ${rating.id}`);
    return rating;
  }

  /**
   * Get user's safety score
   */
  async getSafetyScore(userId: string) {
    let safetyScore = await prisma.safetyScore.findUnique({
      where: { userId },
    });

    if (!safetyScore) {
      safetyScore = await prisma.safetyScore.create({
        data: { userId },
      });
    }

    return safetyScore;
  }

  /**
   * Get user's active walk
   */
  async getActiveWalk(userId: string) {
    const walk = await prisma.safetyWalk.findFirst({
      where: {
        OR: [{ requesterId: userId }, { companionId: userId }],
        status: { in: [SafetyWalkStatus.PENDING, SafetyWalkStatus.ACCEPTED, SafetyWalkStatus.ACTIVE] },
      },
      include: {
        requester: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        companion: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        chat: true,
        locationUpdates: {
          orderBy: { timestamp: 'desc' },
          take: 2,
        },
      },
    });

    return walk;
  }

  /**
   * Get walk history
   */
  async getWalkHistory(userId: string, limit: number = 20, offset: number = 0) {
    const walks = await prisma.safetyWalk.findMany({
      where: {
        OR: [{ requesterId: userId }, { companionId: userId }],
        status: { in: [SafetyWalkStatus.COMPLETED, SafetyWalkStatus.CANCELLED, SafetyWalkStatus.SOS_TRIGGERED] },
      },
      include: {
        requester: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
        companion: { select: { id: true, username: true, displayName: true, avatarUrl: true, avatarConfig: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: limit,
      skip: offset,
    });

    const total = await prisma.safetyWalk.count({
      where: {
        OR: [{ requesterId: userId }, { companionId: userId }],
        status: { in: [SafetyWalkStatus.COMPLETED, SafetyWalkStatus.CANCELLED, SafetyWalkStatus.SOS_TRIGGERED] },
      },
    });

    return { walks, total, limit, offset };
  }

  /**
   * Helper: Increment safety score walk counts
   */
  private async incrementSafetyScoreWalks(
    userId: string,
    completed: boolean,
    lateCancellation: boolean = false
  ) {
    const safetyScore = await prisma.safetyScore.upsert({
      where: { userId },
      update: {
        totalWalks: { increment: 1 },
        ...(completed && { completedWalks: { increment: 1 } }),
        ...(lateCancellation && { cancelledWalks: { increment: 1 } }),
        lastUpdatedAt: new Date(),
      },
      create: {
        userId,
        totalWalks: 1,
        completedWalks: completed ? 1 : 0,
        cancelledWalks: lateCancellation ? 1 : 0,
      },
    });

    // Recalculate score
    await this.recalculateSafetyScore(userId);
    return safetyScore;
  }

  /**
   * Helper: Recalculate safety score
   */
  private async recalculateSafetyScore(userId: string) {
    // Get all ratings for user
    const ratings = await prisma.safetyWalkRating.findMany({
      where: { ratedId: userId },
    });

    const safetyScore = await prisma.safetyScore.findUnique({
      where: { userId },
    });

    if (!safetyScore) return;

    // Calculate components
    const avgRating = ratings.length > 0
      ? ratings.reduce((sum, r) => sum + r.score, 0) / ratings.length
      : 5;

    const completionRate = safetyScore.totalWalks > 0
      ? safetyScore.completedWalks / safetyScore.totalWalks
      : 1;

    const walksBonus = Math.min(safetyScore.totalWalks, 50);

    // Recency bonus: higher if active recently
    const daysSinceUpdate = (Date.now() - safetyScore.lastUpdatedAt.getTime()) / (1000 * 60 * 60 * 24);
    const recencyBonus = Math.max(0, 10 - daysSinceUpdate);

    // Calculate score: 0.4 * rating + 0.3 * completion + 0.2 * walks + 0.1 * recency
    const score = Math.min(100, Math.max(0,
      0.4 * (avgRating / 5 * 100) +
      0.3 * (completionRate * 100) +
      0.2 * walksBonus * 2 +
      0.1 * recencyBonus * 10
    ));

    await prisma.safetyScore.update({
      where: { userId },
      data: {
        score,
        avgRating,
        lastUpdatedAt: new Date(),
      },
    });
  }
}

export const safetyWalkService = new SafetyWalkService();
