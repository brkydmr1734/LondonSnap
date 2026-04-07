import cron from 'node-cron';
import { prisma } from '../../index';
import { logger } from '../utils/logger';
import { notificationService } from '../../notifications/services/notification.service';
import { websocketService } from '../../chat/services/websocket.service';
import { tflService } from '../../transport/services/tfl.service';
import dayjs from 'dayjs';

export const initializeJobs = () => {
  logger.info('Initializing background jobs...');

  // Delete expired snaps - runs every hour
  cron.schedule('0 * * * *', async () => {
    try {
      const result = await prisma.snap.deleteMany({
        where: { expiresAt: { lt: new Date() } },
      });
      logger.info(`Deleted ${result.count} expired snaps`);
    } catch (error) {
      logger.error('Error deleting expired snaps:', error);
    }
  });

  // Delete expired stories - runs every hour
  cron.schedule('0 * * * *', async () => {
    try {
      const result = await prisma.story.deleteMany({
        where: { expiresAt: { lt: new Date() } },
      });
      logger.info(`Deleted ${result.count} expired stories`);
    } catch (error) {
      logger.error('Error deleting expired stories:', error);
    }
  });

  // Check streaks and send warnings - runs every hour
  cron.schedule('0 * * * *', async () => {
    try {
      const warningThreshold = dayjs().add(4, 'hours').toDate();
      
      const expiringStreaks = await prisma.streak.findMany({
        where: {
          isActive: true,
          expiresAt: {
            gt: new Date(),
            lt: warningThreshold,
          },
        },
        include: {
          sender: { select: { id: true, displayName: true } },
          receiver: { select: { id: true, displayName: true } },
        },
      });

      for (const streak of expiringStreaks) {
        const hoursLeft = Math.ceil(dayjs(streak.expiresAt).diff(dayjs(), 'hour'));
        
        await Promise.all([
          notificationService.sendPushNotification(streak.senderId, {
            type: 'STREAK_WARNING',
            title: 'Streak Expiring!',
            body: `Your ${streak.count} day streak with ${streak.receiver.displayName} expires in ${hoursLeft} hours!`,
            data: { streakId: streak.id, friendId: streak.receiverId },
          }),
          notificationService.sendPushNotification(streak.receiverId, {
            type: 'STREAK_WARNING',
            title: 'Streak Expiring!',
            body: `Your ${streak.count} day streak with ${streak.sender.displayName} expires in ${hoursLeft} hours!`,
            data: { streakId: streak.id, friendId: streak.senderId },
          }),
        ]);
      }

      logger.info(`Sent ${expiringStreaks.length * 2} streak warning notifications`);
    } catch (error) {
      logger.error('Error checking streaks:', error);
    }
  });

  // Expire streaks - runs every 15 minutes
  cron.schedule('*/15 * * * *', async () => {
    try {
      const expiredStreaks = await prisma.streak.findMany({
        where: {
          isActive: true,
          expiresAt: { lt: new Date() },
        },
        include: {
          sender: { select: { id: true, displayName: true } },
          receiver: { select: { id: true, displayName: true } },
        },
      });

      for (const streak of expiredStreaks) {
        await prisma.streak.update({
          where: { id: streak.id },
          data: { isActive: false },
        });

        await Promise.all([
          notificationService.sendPushNotification(streak.senderId, {
            type: 'STREAK_LOST',
            title: 'Streak Lost',
            body: `Your ${streak.count} day streak with ${streak.receiver.displayName} has ended.`,
            data: { friendId: streak.receiverId },
          }),
          notificationService.sendPushNotification(streak.receiverId, {
            type: 'STREAK_LOST',
            title: 'Streak Lost',
            body: `Your ${streak.count} day streak with ${streak.sender.displayName} has ended.`,
            data: { friendId: streak.senderId },
          }),
        ]);
      }

      logger.info(`Expired ${expiredStreaks.length} streaks`);
    } catch (error) {
      logger.error('Error expiring streaks:', error);
    }
  });

  // Clean up expired verification codes - runs daily at 3 AM
  cron.schedule('0 3 * * *', async () => {
    try {
      const result = await prisma.verificationCode.deleteMany({
        where: { expiresAt: { lt: new Date() } },
      });
      logger.info(`Deleted ${result.count} expired verification codes`);
    } catch (error) {
      logger.error('Error deleting verification codes:', error);
    }
  });

  // Mark offline users - runs every 5 minutes
  cron.schedule('*/5 * * * *', async () => {
    try {
      const threshold = dayjs().subtract(5, 'minutes').toDate();
      
      const result = await prisma.user.updateMany({
        where: {
          isOnline: true,
          lastSeenAt: { lt: threshold },
        },
        data: { isOnline: false },
      });

      if (result.count > 0) {
        logger.info(`Marked ${result.count} users as offline`);
      }
    } catch (error) {
      logger.error('Error marking users offline:', error);
    }
  });

  // Delete expired messages (disappearing messages) - runs every 15 minutes
  cron.schedule('*/15 * * * *', async () => {
    try {
      // First, find affected chat IDs before deletion
      const expiredMessages = await prisma.message.findMany({
        where: {
          expiresAt: { lt: new Date(), not: null },
        },
        select: { id: true, chatId: true },
      });

      if (expiredMessages.length === 0) return;

      // Group by chatId and notify via WebSocket
      const chatMessageMap = new Map<string, string[]>();
      for (const msg of expiredMessages) {
        if (!chatMessageMap.has(msg.chatId)) {
          chatMessageMap.set(msg.chatId, []);
        }
        chatMessageMap.get(msg.chatId)!.push(msg.id);
      }

      // Delete expired messages
      const result = await prisma.message.deleteMany({
        where: {
          expiresAt: { lt: new Date(), not: null },
        },
      });

      // Emit message_expired events to affected chats
      for (const [chatId, messageIds] of chatMessageMap) {
        websocketService.emitMessagesExpired(chatId, messageIds);
      }

      if (result.count > 0) {
        logger.info(`Deleted ${result.count} expired messages`);
      }
    } catch (error) {
      logger.error('Error deleting expired messages:', error);
    }
  });

  // Fetch tube status every 3 minutes
  cron.schedule('*/3 * * * *', async () => {
    try {
      await tflService.fetchAndCacheStatus();
      logger.info('Tube status updated');
    } catch (error) {
      logger.error('Error fetching tube status:', error);
    }
  });

  // Fetch tube status on startup to warm the cache
  tflService.fetchAndCacheStatus()
    .then(() => logger.info('Initial tube status fetched'))
    .catch((error) => logger.error('Error fetching initial tube status:', error));

  logger.info('Background jobs initialized');
};
