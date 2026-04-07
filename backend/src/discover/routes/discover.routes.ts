import { Router } from 'express';
import { discoverController } from '../controllers/discover.controller';

const router = Router();

// Search
router.get('/search', discoverController.search);

// Discover users
router.get('/users', discoverController.discoverUsers);

// Discover stories
router.get('/stories', discoverController.discoverStories);

// Discover events
router.get('/events', discoverController.discoverEvents);

// Students nearby (privacy-safe)
router.get('/nearby', discoverController.studentsNearby);

// Social matching
router.post('/match', discoverController.createMatch);
router.get('/matches', discoverController.getMatches);
router.post('/matches/:matchId/respond', discoverController.respondToMatch);

export default router;
