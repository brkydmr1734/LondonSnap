import { Router } from 'express';
import { notificationController } from '../controllers/notification.controller';

const router = Router();

// Get notifications (paginated)
router.get('/', notificationController.getNotifications);

// Device registration for push notifications
router.post('/device', notificationController.registerDevice);
router.delete('/device', notificationController.unregisterDevice);

// Notification management
router.post('/:notificationId/read', notificationController.markAsRead);
router.post('/read-all', notificationController.markAllAsRead);
router.delete('/:notificationId', notificationController.deleteNotification);
router.delete('/', notificationController.clearAll);

export default router;
