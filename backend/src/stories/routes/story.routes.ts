import { Router } from 'express';
import { storyController } from '../controllers/story.controller';
import { storyRateLimiter } from '../../common/middleware/rateLimiter';

const router = Router();

// Post story
router.post('/', storyRateLimiter, storyController.postStory);

// Get stories feed
router.get('/feed', storyController.getStoriesFeed);

// Get my stories
router.get('/me', storyController.getMyStories);

// Get user's stories
router.get('/user/:userId', storyController.getUserStories);

// View story
router.post('/:storyId/view', storyController.viewStory);

// Get story viewers
router.get('/:storyId/viewers', storyController.getStoryViewers);

// React to story
router.post('/:storyId/react', storyController.reactToStory);

// Reply to story
router.post('/:storyId/reply', storyController.replyToStory);

// Delete story
router.delete('/:storyId', storyController.deleteStory);

// Update story settings
router.put('/:storyId/settings', storyController.updateStorySettings);

export default router;
