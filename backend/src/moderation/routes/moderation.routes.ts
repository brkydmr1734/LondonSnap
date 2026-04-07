import { Router } from 'express';
import { moderationController } from '../controllers/moderation.controller';
import { authMiddleware } from '../../auth/middleware/auth.middleware';
import { requireAdmin } from '../../admin/middleware/admin.middleware';

const router = Router();

// Reports (user endpoints - require auth)
router.post('/report', authMiddleware, moderationController.createReport);
router.get('/reports', authMiddleware, moderationController.getReports);
router.get('/reports/:reportId', authMiddleware, moderationController.getReportById);
router.put('/reports/:reportId', authMiddleware, moderationController.updateReport);

// Admin: Get all reports (requires auth + admin)
router.get('/admin/reports', authMiddleware, requireAdmin, moderationController.getAllReports);

// Admin: User management (requires auth + admin)
router.post('/admin/users/:userId/suspend', authMiddleware, requireAdmin, moderationController.suspendUser);
router.post('/admin/users/:userId/unsuspend', authMiddleware, requireAdmin, moderationController.unsuspendUser);
router.post('/admin/users/:userId/ban', authMiddleware, requireAdmin, moderationController.banUser);

export default router;
