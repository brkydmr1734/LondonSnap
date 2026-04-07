import { Router } from 'express';
import { safetyWalkController } from '../controllers/safety-walk.controller';
import { authMiddleware } from '../../auth/middleware/auth.middleware';
import rateLimit from 'express-rate-limit';

const router = Router();

// All routes require authentication
router.use(authMiddleware);

// SOS rate limit: max 3 per hour (prevent abuse)
const sosLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3,
  message: { success: false, error: 'Too many SOS requests, please try again later' },
  standardHeaders: true,
  legacyHeaders: false,
});

// Location update rate limit: max 60 per minute
const locationLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 60,
  message: { success: false, error: 'Too many location updates' },
  standardHeaders: true,
  legacyHeaders: false,
});

// Find potential companions
router.post('/find-companions', safetyWalkController.findCompanions);

// Create a walk request
router.post('/request', safetyWalkController.createWalkRequest);

// Accept a walk request
router.post('/:walkId/accept', safetyWalkController.acceptWalk);

// Decline a walk request
router.post('/:walkId/decline', safetyWalkController.declineWalk);

// Start a walk
router.post('/:walkId/start', safetyWalkController.startWalk);

// Update location during walk (rate limited)
router.post('/:walkId/location', locationLimiter, safetyWalkController.updateLocation);

// Trigger SOS (rate limited)
router.post('/:walkId/sos', sosLimiter, safetyWalkController.triggerSOS);

// Complete a walk
router.post('/:walkId/complete', safetyWalkController.completeWalk);

// Rate companion after walk
router.post('/:walkId/rate', safetyWalkController.rateCompanion);

// Get active walk
router.get('/active', safetyWalkController.getActiveWalk);

// Get safety score
router.get('/score', safetyWalkController.getSafetyScore);

// Get walk history
router.get('/history', safetyWalkController.getWalkHistory);

// Cancel a walk
router.delete('/:walkId', safetyWalkController.cancelWalk);

export default router;
