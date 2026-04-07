import { Router } from 'express';
import { memoryController } from '../controllers/memory.controller';
import { requireVaultAccess } from '../middleware/vault.middleware';

const router = Router();

// Get user's memories (paginated)
router.get('/', memoryController.getMemories);

// ========================================
// MY EYES ONLY VAULT ROUTES
// ========================================

// Check vault status (no PIN required)
router.get('/my-eyes-only/status', memoryController.getVaultStatus);

// Setup vault PIN
router.post('/my-eyes-only/setup', memoryController.setupVault);

// Verify PIN and get vault token
router.post('/my-eyes-only/verify', memoryController.verifyVault);

// Change vault PIN
router.post('/my-eyes-only/change-pin', memoryController.changeVaultPin);

// Get My Eyes Only memories (requires vault token)
router.get('/my-eyes-only', requireVaultAccess, memoryController.getMyEyesOnlyMemories);

// ========================================
// ALBUMS
// ========================================

// Get user's albums
router.get('/albums', memoryController.getAlbums);

// Save to memories
router.post('/', memoryController.createMemory);

// Create album
router.post('/albums', memoryController.createAlbum);

// Update album
router.put('/albums/:id', memoryController.updateAlbum);

// Update memory
router.patch('/:id', memoryController.updateMemory);

// Delete memory
router.delete('/:id', memoryController.deleteMemory);

// Move memory to My Eyes Only vault
router.post('/:id/move-to-vault', memoryController.moveToVault);

// Move memory from My Eyes Only vault (requires vault token)
router.post('/:id/move-from-vault', requireVaultAccess, memoryController.moveFromVault);

// Reshare memory as story
router.post('/:id/reshare', memoryController.reshareAsStory);

export default router;
