import { Router } from 'express';
import { socialController } from '../controllers/social.controller';

const router = Router();

// Friend requests
router.post('/friends/request/:userId', socialController.sendFriendRequest);
router.post('/friends/accept/:requestId', socialController.acceptFriendRequest);
router.post('/friends/decline/:requestId', socialController.declineFriendRequest);
router.get('/friends/requests/pending', socialController.getPendingRequests);
router.get('/friends/requests/sent', socialController.getSentRequests);

// Friends list
router.get('/friends', socialController.getFriends);
router.delete('/friends/:friendId', socialController.removeFriend);
router.put('/friends/:friendId/level', socialController.updateFriendLevel);

// Snap score
router.get('/snap-score', socialController.getSnapScore);

// Block
router.post('/block/:userId', socialController.blockUser);
router.delete('/block/:userId', socialController.unblockUser);
router.get('/blocked', socialController.getBlockedUsers);

// Friend suggestions
router.get('/friends/suggestions', socialController.getFriendSuggestions);

// Mutual friends
router.get('/friends/mutual/:userId', socialController.getMutualFriends);

export default router;
