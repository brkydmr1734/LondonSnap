import { Router } from 'express';
import { transportController } from '../controllers/transport.controller';

const router = Router();

// GET /api/v1/transport/tube-status - Public endpoint (no auth required)
router.get('/tube-status', transportController.getTubeStatus);

// GET /api/v1/transport/route - Route planning between two coordinates
router.get('/route', transportController.getRouteOptions);

// GET /api/v1/transport/nearby-stops - Find nearby transport stops
router.get('/nearby-stops', transportController.getNearbyStops);

export default router;
