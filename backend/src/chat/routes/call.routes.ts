import { Router } from 'express';
import { callController } from '../controllers/call.controller';

const router = Router();

// Get call history (paginated)
router.get('/history', callController.getCallHistory);

// Get TURN server credentials
router.get('/turn-credentials', callController.getTurnCredentials);

export default router;
