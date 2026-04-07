import { Router } from 'express';
import { chatWithAI } from '../controllers/ai.controller';

const router = Router();

// POST /api/v1/ai/chat - Chat with AI
router.post('/chat', chatWithAI);

export default router;
