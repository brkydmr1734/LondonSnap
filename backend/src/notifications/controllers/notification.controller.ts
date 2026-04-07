import { Request, Response, NextFunction } from 'express';
import { notificationService } from '../services/notification.service';
import { BadRequestError } from '../../common/utils/AppError';

export class NotificationController {
  /**
   * GET /api/v1/notifications
   * Get user notifications with pagination
   */
  async getNotifications(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { limit = 50, offset = 0 } = req.query;

      const result = await notificationService.getNotifications(
        req.user.id,
        Number(limit),
        Number(offset)
      );

      res.json({ success: true, data: result });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /api/v1/notifications/device
   * Register a device for push notifications
   */
  async registerDevice(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      
      const { token, platform } = req.body;

      if (!token || typeof token !== 'string') {
        throw new BadRequestError('Device token is required');
      }

      if (!platform || !['IOS', 'ANDROID'].includes(platform)) {
        throw new BadRequestError('Valid platform (IOS or ANDROID) is required');
      }

      const result = await notificationService.registerDeviceToken(
        req.user.id,
        token,
        platform
      );

      res.json({ success: result.success, message: result.message });
    } catch (error) {
      next(error);
    }
  }

  /**
   * DELETE /api/v1/notifications/device
   * Unregister device(s) from push notifications
   */
  async unregisterDevice(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      
      const { platform } = req.query;

      // Validate platform if provided
      if (platform && !['IOS', 'ANDROID'].includes(platform as string)) {
        throw new BadRequestError('Invalid platform');
      }

      const result = await notificationService.unregisterDeviceToken(
        req.user.id,
        platform as 'IOS' | 'ANDROID' | undefined
      );

      res.json({ success: result.success, message: result.message });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /api/v1/notifications/:notificationId/read
   * Mark a specific notification as read
   */
  async markAsRead(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { notificationId } = req.params;

      await notificationService.markAsRead(req.user.id, notificationId);
      res.json({ success: true, message: 'Marked as read' });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /api/v1/notifications/read-all
   * Mark all notifications as read
   */
  async markAllAsRead(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      await notificationService.markAllAsRead(req.user.id);
      res.json({ success: true, message: 'All marked as read' });
    } catch (error) {
      next(error);
    }
  }

  /**
   * DELETE /api/v1/notifications/:notificationId
   * Delete a specific notification
   */
  async deleteNotification(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { notificationId } = req.params;

      await notificationService.deleteNotification(req.user.id, notificationId);
      res.json({ success: true, message: 'Notification deleted' });
    } catch (error) {
      next(error);
    }
  }

  /**
   * DELETE /api/v1/notifications
   * Clear all notifications
   */
  async clearAll(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      await notificationService.clearAllNotifications(req.user.id);
      res.json({ success: true, message: 'All notifications cleared' });
    } catch (error) {
      next(error);
    }
  }
}

export const notificationController = new NotificationController();
