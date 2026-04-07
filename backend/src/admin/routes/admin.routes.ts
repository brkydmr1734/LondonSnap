import { Router } from 'express';
import { adminController } from '../controllers/admin.controller';
import { authMiddleware } from '../../auth/middleware/auth.middleware';
import { requireAdmin } from '../middleware/admin.middleware';

const router = Router();

// Public: Admin login (no auth required)
router.post('/login', adminController.login);

// All routes below require auth + admin
router.use(authMiddleware, requireAdmin);

// Dashboard
router.get('/dashboard/stats', adminController.getDashboardStats);
router.get('/dashboard/activity', adminController.getDashboardActivity);

// Users
router.get('/users', adminController.getUsers);
router.get('/users/:userId', adminController.getUserDetail);
router.post('/users/:userId/suspend', adminController.suspendUser);
router.post('/users/:userId/unsuspend', adminController.unsuspendUser);
router.post('/users/:userId/ban', adminController.banUser);

// Reports
router.get('/reports', adminController.getReports);
router.patch('/reports/:reportId/resolve', adminController.resolveReport);
router.patch('/reports/:reportId/dismiss', adminController.dismissReport);

// Events
router.get('/events', adminController.getEvents);
router.patch('/events/:eventId/status', adminController.updateEventStatus);
router.delete('/events/:eventId', adminController.deleteEvent);

// Universities
router.get('/universities', adminController.getUniversities);
router.post('/universities', adminController.createUniversity);
router.put('/universities/:universityId', adminController.updateUniversity);
router.delete('/universities/:universityId', adminController.deleteUniversity);

export default router;
