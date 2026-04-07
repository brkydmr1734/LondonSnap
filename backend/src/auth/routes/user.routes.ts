import { Router } from 'express';
import { userController } from '../controllers/user.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

// Profile routes
router.get('/profile/:userId?', userController.getProfile);
router.put('/profile', userController.updateProfile);
router.put('/profile/avatar', userController.updateAvatar);
router.put('/profile/avatar-config', userController.updateAvatarConfig);

// Privacy settings
router.get('/privacy', userController.getPrivacySettings);
router.put('/privacy', userController.updatePrivacySettings);

// Notification preferences
router.get('/notifications/preferences', userController.getNotificationPreferences);
router.put('/notifications/preferences', userController.updateNotificationPreferences);

// Search users
router.get('/search', userController.searchUsers);

// Get user by username
router.get('/username/:username', userController.getUserByUsername);

// Sessions
router.get('/sessions', userController.getSessions);
router.delete('/sessions/:sessionId', userController.revokeSession);

// Interests
router.get('/interests', userController.getInterests);
router.put('/interests', userController.updateInterests);

// Device tokens
router.post('/device-token', userController.registerDeviceToken);
router.delete('/device-token', userController.removeDeviceToken);

// Location
router.put('/location', userController.updateLocation);
router.get('/friend-locations', userController.getFriendLocations);

export default router;
