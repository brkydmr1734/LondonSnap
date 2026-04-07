import { Router } from 'express';
import { mediaController } from '../controllers/media.controller';
import multer from 'multer';

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 100 * 1024 * 1024 }, // 100MB
});

const router = Router();

// Get presigned upload URL
router.post('/upload-url', mediaController.getUploadUrl);

// Upload media directly
router.post('/upload', upload.single('file'), mediaController.uploadMedia);

// Get media by ID
router.get('/:mediaId', mediaController.getMedia);

// Delete media
router.delete('/:mediaId', mediaController.deleteMedia);

export default router;
