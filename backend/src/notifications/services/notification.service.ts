import * as admin from 'firebase-admin';
import { prisma } from '../../index';
import { logger } from '../../common/utils/logger';

// Firebase Admin SDK Configuration
// Initialize with service account credentials from environment
let firebaseInitialized = false;

try {
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (serviceAccountJson) {
    const serviceAccount = JSON.parse(serviceAccountJson);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    firebaseInitialized = true;
    logger.info('Firebase Admin SDK initialized successfully');
  } else if (process.env.FIREBASE_PROJECT_ID) {
    // Fallback: use individual env vars
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL || '',
        privateKey: (process.env.FIREBASE_PRIVATE_KEY || '').replace(/\\n/g, '\n'),
      }),
    });
    firebaseInitialized = true;
    logger.info('Firebase Admin SDK initialized with individual credentials');
  } else {
    logger.warn('Firebase credentials missing - push notifications disabled');
  }
} catch (error) {
  logger.warn('Firebase Admin SDK not initialized - push notifications disabled:', error);
}

interface PushNotificationData {
  type: string;
  title: string;
  body: string;
  imageUrl?: string;
  data?: Record<string, string>;
}

export class NotificationService {
  /**
   * Register a device token for push notifications
   * Simply stores the FCM token in the database (no SNS endpoint needed)
   */
  async registerDeviceToken(
    userId: string,
    token: string,
    platform: 'IOS' | 'ANDROID'
  ): Promise<{ success: boolean; message: string }> {
    try {
      // Check if user already has a device token for this platform
      const existingToken = await prisma.deviceToken.findFirst({
        where: { userId, platform },
      });

      // If token exists and is the same, just return success
      if (existingToken && existingToken.token === token) {
        return { success: true, message: 'Device already registered' };
      }

      // Upsert device token record
      if (existingToken) {
        await prisma.deviceToken.update({
          where: { id: existingToken.id },
          data: {
            token,
            isActive: true,
            updatedAt: new Date(),
          },
        });
      } else {
        await prisma.deviceToken.create({
          data: {
            userId,
            token,
            platform,
            isActive: true,
          },
        });
      }

      logger.info(`Device token registered for user ${userId} on ${platform}`);
      return { success: true, message: 'Device registered successfully' };
    } catch (error) {
      logger.error('Failed to register device token:', error);
      return { success: false, message: 'Failed to register device' };
    }
  }

  /**
   * Unregister device token(s) for a user
   */
  async unregisterDeviceToken(
    userId: string,
    platform?: 'IOS' | 'ANDROID'
  ): Promise<{ success: boolean; message: string }> {
    try {
      const whereClause = platform
        ? { userId, platform }
        : { userId };

      // Delete from database
      await prisma.deviceToken.deleteMany({
        where: whereClause,
      });

      logger.info(`Device token(s) unregistered for user ${userId}`);
      return { success: true, message: 'Device(s) unregistered successfully' };
    } catch (error) {
      logger.error('Failed to unregister device token:', error);
      return { success: false, message: 'Failed to unregister device' };
    }
  }

  /**
   * Send push notification to a user via Firebase Cloud Messaging
   * Respects notification preferences and quiet hours
   */
  async sendPushNotification(userId: string, notification: PushNotificationData) {
    try {
      // Check notification preferences
      const prefs = await prisma.notificationPreferences.findUnique({
        where: { userId },
      });

      if (prefs && !prefs.pushEnabled) {
        return;
      }

      // Check specific notification types
      if (prefs) {
        const typePrefs: Record<string, boolean> = {
          SNAP_RECEIVED: prefs.snapNotifications,
          SNAP_OPENED: prefs.snapNotifications,
          SNAP_SCREENSHOT: prefs.snapNotifications,
          MESSAGE: prefs.chatNotifications,
          STORY_REACTION: prefs.storyNotifications,
          STORY_REPLY: prefs.storyNotifications,
          FRIEND_REQUEST: prefs.friendNotifications,
          FRIEND_ACCEPTED: prefs.friendNotifications,
          EVENT_INVITE: prefs.eventNotifications,
          EVENT_REMINDER: prefs.eventNotifications,
          STREAK_WARNING: prefs.streakReminders,
          STREAK_LOST: prefs.streakReminders,
        };

        if (typePrefs[notification.type] === false) {
          return;
        }

        // Check quiet hours
        if (prefs.quietHoursStart && prefs.quietHoursEnd) {
          const now = new Date();
          const hours = now.getHours();
          const startHour = parseInt(prefs.quietHoursStart.split(':')[0]);
          const endHour = parseInt(prefs.quietHoursEnd.split(':')[0]);

          if (startHour < endHour) {
            if (hours >= startHour && hours < endHour) return;
          } else {
            if (hours >= startHour || hours < endHour) return;
          }
        }
      }

      // Store notification in database
      await prisma.notification.create({
        data: {
          userId,
          type: notification.type as any,
          title: notification.title,
          body: notification.body,
          imageUrl: notification.imageUrl,
          data: notification.data,
        },
      });

      // Send via Firebase Cloud Messaging
      if (firebaseInitialized) {
        const deviceTokens = await prisma.deviceToken.findMany({
          where: {
            userId,
            isActive: true,
          },
        });

        for (const device of deviceTokens) {
          try {
            const message: admin.messaging.Message = {
              token: device.token,
              notification: {
                title: notification.title,
                body: notification.body,
                ...(notification.imageUrl ? { imageUrl: notification.imageUrl } : {}),
              },
              data: {
                type: notification.type,
                ...(notification.data || {}),
              },
              ...(device.platform === 'IOS'
                ? {
                    apns: {
                      payload: {
                        aps: {
                          sound: 'default',
                          badge: 1,
                          'mutable-content': 1,
                        },
                      },
                    },
                  }
                : {
                    android: {
                      priority: 'high' as const,
                      notification: {
                        sound: 'default',
                        channelId: 'londonsnaps_notifications',
                      },
                    },
                  }),
            };

            await admin.messaging().send(message);
            logger.info(`Push notification sent to ${userId} via FCM (${device.platform})`);
          } catch (pushError: any) {
            // Handle invalid/expired token
            if (
              pushError.code === 'messaging/invalid-registration-token' ||
              pushError.code === 'messaging/registration-token-not-registered'
            ) {
              logger.warn(`FCM token invalid for user ${userId}, marking inactive`);
              await this.handleInvalidToken(device.id);
            } else {
              logger.error(`FCM send failed for ${device.platform}:`, pushError);
            }
          }
        }
      }
    } catch (error) {
      logger.error('Failed to send push notification:', error);
    }
  }

  /**
   * Handle invalid FCM token - mark as inactive
   */
  private async handleInvalidToken(deviceTokenId: string): Promise<void> {
    try {
      await prisma.deviceToken.update({
        where: { id: deviceTokenId },
        data: { isActive: false },
      });
    } catch (error) {
      logger.error('Failed to handle invalid token:', error);
    }
  }

  /**
   * Send notification to multiple users
   */
  async sendBulkNotification(userIds: string[], notification: PushNotificationData) {
    await Promise.all(
      userIds.map(userId => this.sendPushNotification(userId, notification))
    );
  }

  /**
   * Get user notifications with pagination
   */
  async getNotifications(userId: string, limit = 50, offset = 0) {
    const notifications = await prisma.notification.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: limit,
      skip: offset,
    });

    const unreadCount = await prisma.notification.count({
      where: {
        userId,
        isRead: false,
      },
    });

    return { notifications, unreadCount };
  }

  /**
   * Mark notification as read
   */
  async markAsRead(userId: string, notificationId: string) {
    await prisma.notification.updateMany({
      where: {
        id: notificationId,
        userId,
      },
      data: { isRead: true },
    });
  }

  /**
   * Mark all notifications as read
   */
  async markAllAsRead(userId: string) {
    await prisma.notification.updateMany({
      where: { userId },
      data: { isRead: true },
    });
  }

  /**
   * Delete a specific notification
   */
  async deleteNotification(userId: string, notificationId: string) {
    await prisma.notification.deleteMany({
      where: {
        id: notificationId,
        userId,
      },
    });
  }

  /**
   * Clear all notifications for a user
   */
  async clearAllNotifications(userId: string) {
    await prisma.notification.deleteMany({
      where: { userId },
    });
  }
}

export const notificationService = new NotificationService();
