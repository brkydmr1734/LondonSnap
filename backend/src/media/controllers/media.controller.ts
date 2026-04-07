import { Request, Response, NextFunction } from 'express';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import sharp from 'sharp';
import { v4 as uuidv4 } from 'uuid';
import path from 'path';
import { prisma } from '../../index';
import { BadRequestError } from '../../common/utils/AppError';
import {
  processVideo,
  isSupportedVideoType,
  isFFmpegAvailable,
  readFileAsBuffer,
  cleanupTempDir,
} from '../services/video.service';

// Supabase Storage Configuration
const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const STORAGE_BUCKET = process.env.SUPABASE_STORAGE_BUCKET || 'media';

// Initialize Supabase client with service role key (server-side)
const supabase: SupabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

/**
 * Upload a buffer to Supabase Storage and return the public URL
 */
async function uploadToStorage(
  key: string,
  buffer: Buffer,
  contentType: string
): Promise<string> {
  const { error } = await supabase.storage
    .from(STORAGE_BUCKET)
    .upload(key, buffer, {
      contentType,
      upsert: true,
    });

  if (error) {
    throw new Error(`Storage upload failed: ${error.message}`);
  }

  const { data: urlData } = supabase.storage
    .from(STORAGE_BUCKET)
    .getPublicUrl(key);

  return urlData.publicUrl;
}

/**
 * Delete a file from Supabase Storage
 */
async function deleteFromStorage(key: string): Promise<void> {
  const { error } = await supabase.storage
    .from(STORAGE_BUCKET)
    .remove([key]);

  if (error) {
    throw new Error(`Storage delete failed: ${error.message}`);
  }
}

export class MediaController {
  async getUploadUrl(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');

      const { contentType, fileName } = req.body;
      if (!contentType) throw new BadRequestError('Content type required');

      const ext = fileName?.split('.').pop() || 'jpg';
      const key = `uploads/${req.user.id}/${uuidv4()}.${ext}`;

      // Create a signed upload URL for direct client uploads
      const { data, error } = await supabase.storage
        .from(STORAGE_BUCKET)
        .createSignedUploadUrl(key);

      if (error) throw new Error(`Failed to create upload URL: ${error.message}`);

      const { data: urlData } = supabase.storage
        .from(STORAGE_BUCKET)
        .getPublicUrl(key);

      res.json({
        success: true,
        data: {
          uploadUrl: data.signedUrl,
          mediaUrl: urlData.publicUrl,
          key,
        },
      });
    } catch (error) {
      next(error);
    }
  }

  async uploadMedia(req: Request, res: Response, next: NextFunction) {
    let tempDir: string | undefined;

    try {
      if (!req.user) throw new BadRequestError('Auth required');
      if (!req.file) throw new BadRequestError('File required');

      const file = req.file;
      const isVideo = file.mimetype.startsWith('video/');
      const isImage = file.mimetype.startsWith('image/');

      let buffer = file.buffer;
      let width: number | undefined;
      let height: number | undefined;
      let duration: number | undefined;
      let thumbnailUrl: string | undefined;
      let mediaUrl: string;
      let finalMimeType = file.mimetype;

      if (isVideo) {
        // ========================
        // VIDEO PROCESSING PIPELINE
        // ========================

        // Check if video type is supported
        if (!isSupportedVideoType(file.mimetype)) {
          throw new BadRequestError(
            `Unsupported video format: ${file.mimetype}. Supported formats: MP4, MOV, WebM, AVI, MKV`
          );
        }

        // Check if FFmpeg is available
        if (!isFFmpegAvailable()) {
          console.warn('FFmpeg not available - uploading video without processing');
          // Fall through to upload without processing
        } else {
          // Process the video
          const result = await processVideo(file.buffer, file.mimetype);
          tempDir = path.dirname(result.processedVideoPath);

          // Read processed files
          buffer = await readFileAsBuffer(result.processedVideoPath);
          const thumbnailBuffer = await readFileAsBuffer(result.thumbnailPath);

          // Extract metadata
          width = result.metadata.width;
          height = result.metadata.height;
          duration = Math.round(result.metadata.duration);
          finalMimeType = result.wasCompressed ? 'video/mp4' : file.mimetype;

          // Upload thumbnail to Supabase Storage
          const thumbnailKey = `uploads/${req.user.id}/thumbnails/${uuidv4()}.jpg`;
          thumbnailUrl = await uploadToStorage(thumbnailKey, thumbnailBuffer, 'image/jpeg');
        }

        // Upload video to Supabase Storage
        const ext = finalMimeType === 'video/mp4' ? 'mp4' : file.originalname.split('.').pop() || 'mp4';
        const videoKey = `uploads/${req.user.id}/${uuidv4()}.${ext}`;
        mediaUrl = await uploadToStorage(videoKey, buffer, finalMimeType);

      } else if (isImage) {
        // ========================
        // IMAGE PROCESSING PIPELINE
        // ========================
        const image = sharp(file.buffer);
        const metadata = await image.metadata();
        width = metadata.width;
        height = metadata.height;

        // Resize if too large
        if (width && width > 2048) {
          buffer = await image.resize(2048, null, { withoutEnlargement: true }).toBuffer();
        }

        // Upload to Supabase Storage
        const ext = file.originalname.split('.').pop() || 'jpg';
        const key = `uploads/${req.user.id}/${uuidv4()}.${ext}`;
        mediaUrl = await uploadToStorage(key, buffer, file.mimetype);

      } else {
        // ========================
        // OTHER MEDIA TYPES (audio, etc.)
        // ========================
        const ext = file.originalname.split('.').pop() || 'bin';
        const key = `uploads/${req.user.id}/${uuidv4()}.${ext}`;
        mediaUrl = await uploadToStorage(key, buffer, file.mimetype);
      }

      // Determine media type
      const mediaType = isImage ? 'IMAGE' : isVideo ? 'VIDEO' : 'AUDIO';

      // Save to database
      const media = await prisma.media.create({
        data: {
          userId: req.user.id,
          url: mediaUrl,
          type: mediaType,
          mimeType: finalMimeType,
          size: buffer.length,
          width,
          height,
          duration,
          thumbnailUrl,
          isProcessed: true,
        },
      });

      res.status(201).json({
        success: true,
        data: {
          media: {
            ...media,
            mediaType, // Include for client convenience
          },
        },
      });
    } catch (error) {
      next(error);
    } finally {
      // Clean up temp directory
      if (tempDir) {
        cleanupTempDir(tempDir).catch(() => {});
      }
    }
  }

  async getMedia(req: Request, res: Response, next: NextFunction) {
    try {
      const { mediaId } = req.params;

      const media = await prisma.media.findUnique({
        where: { id: mediaId },
      });

      if (!media) throw new BadRequestError('Media not found');

      res.json({ success: true, data: { media } });
    } catch (error) {
      next(error);
    }
  }

  async deleteMedia(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Auth required');
      const { mediaId } = req.params;

      const media = await prisma.media.findFirst({
        where: { id: mediaId, userId: req.user.id },
      });

      if (!media) throw new BadRequestError('Media not found');

      // Extract storage key from the public URL
      // Supabase public URLs: {SUPABASE_URL}/storage/v1/object/public/{bucket}/{key}
      const urlPrefix = `${SUPABASE_URL}/storage/v1/object/public/${STORAGE_BUCKET}/`;
      const key = media.url.replace(urlPrefix, '');

      if (key && key !== media.url) {
        await deleteFromStorage(key);
      }

      await prisma.media.delete({ where: { id: mediaId } });

      res.json({ success: true, message: 'Media deleted' });
    } catch (error) {
      next(error);
    }
  }
}

export const mediaController = new MediaController();
