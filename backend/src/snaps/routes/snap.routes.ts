import { Router } from 'express';
import { snapController } from '../controllers/snap.controller';
import { snapRateLimiter } from '../../common/middleware/rateLimiter';

const router = Router();

// Send snap
router.post('/', snapRateLimiter, snapController.sendSnap);

// Get received snaps
router.get('/received', snapController.getReceivedSnaps);

// Get sent snaps
router.get('/sent', snapController.getSentSnaps);

// Open snap
router.post('/:snapId/open', snapController.openSnap);

// Report screenshot
router.post('/:snapId/screenshot', snapController.reportScreenshot);

// Get snap status (for sender)
router.get('/:snapId/status', snapController.getSnapStatus);

// Get streaks
router.get('/streaks', snapController.getStreaks);

// Saved snaps
router.get('/saved', snapController.getSavedSnaps);
router.post('/:snapId/save', snapController.saveSnap);
router.delete('/:snapId/save', snapController.unsaveSnap);
router.get('/:snapId/saved', snapController.isSnapSaved);

export default router;
