import { Router } from 'express';
import { chatController } from '../controllers/chat.controller';
import { messageRateLimiter } from '../../common/middleware/rateLimiter';

const router = Router();

// Get all chats
router.get('/', chatController.getChats);

// Create new chat (group)
router.post('/', chatController.createChat);

// Get chat by ID
router.get('/:chatId', chatController.getChatById);

// Delete chat for current user
router.delete('/:chatId', chatController.deleteChat);

// Get chat messages
router.get('/:chatId/messages', chatController.getMessages);

// Send message
router.post('/:chatId/messages', messageRateLimiter, chatController.sendMessage);

// Edit message
router.put('/:chatId/messages/:messageId', chatController.editMessage);

// Delete message
router.delete('/:chatId/messages/:messageId', chatController.deleteMessage);

// React to message
router.post('/:chatId/messages/:messageId/react', chatController.reactToMessage);

// Get or create direct chat
router.post('/direct/:userId', chatController.getOrCreateDirectChat);

// Update chat settings
router.put('/:chatId', chatController.updateChat);

// Add member to group
router.post('/:chatId/members', chatController.addMember);

// Remove member from group
router.delete('/:chatId/members/:userId', chatController.removeMember);

// Leave chat
router.post('/:chatId/leave', chatController.leaveChat);

// Mute chat
router.post('/:chatId/mute', chatController.muteChat);

// Unmute chat
router.post('/:chatId/unmute', chatController.unmuteChat);

// Mark messages as read
router.post('/:chatId/read', chatController.markAsRead);

// Mark messages as delivered
router.post('/:chatId/messages/delivered', chatController.markAsDelivered);

export default router;
