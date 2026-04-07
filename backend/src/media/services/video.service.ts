import ffmpeg from 'fluent-ffmpeg';
import ffmpegInstaller from '@ffmpeg-installer/ffmpeg';
import { promises as fs } from 'fs';
import path from 'path';
import os from 'os';
import { v4 as uuidv4 } from 'uuid';

// Configure ffmpeg path
let ffmpegAvailable = true;
try {
  ffmpeg.setFfmpegPath(ffmpegInstaller.path);
} catch (error) {
  console.warn('FFmpeg not available. Video processing will be disabled.');
  ffmpegAvailable = false;
}

export interface VideoMetadata {
  duration: number;
  width: number;
  height: number;
  codec: string;
  bitrate?: number;
  fps?: number;
}

export interface VideoProcessingResult {
  processedVideoPath: string;
  thumbnailPath: string;
  metadata: VideoMetadata;
  wasCompressed: boolean;
}

// Supported video MIME types
const SUPPORTED_VIDEO_TYPES = [
  'video/mp4',
  'video/quicktime',
  'video/webm',
  'video/x-msvideo',
  'video/x-matroska',
  'video/mpeg',
  'video/3gpp',
  'video/x-m4v',
];

// Supported codecs for direct upload (no re-encoding needed)
const SUPPORTED_CODECS = ['h264', 'hevc', 'vp8', 'vp9', 'av1'];

// Max video duration in seconds
const MAX_DURATION_SECONDS = 60;

// Max dimensions before compression
const MAX_WIDTH = 1920;
const MAX_HEIGHT = 1080;

// Thumbnail settings
const THUMBNAIL_MAX_WIDTH = 480;
const THUMBNAIL_QUALITY = 80;

/**
 * Check if FFmpeg is available
 */
export function isFFmpegAvailable(): boolean {
  return ffmpegAvailable;
}

/**
 * Check if the MIME type is a supported video format
 */
export function isSupportedVideoType(mimeType: string): boolean {
  return SUPPORTED_VIDEO_TYPES.includes(mimeType);
}

/**
 * Probe video file to extract metadata
 */
export async function probeVideo(filePath: string): Promise<VideoMetadata> {
  return new Promise((resolve, reject) => {
    ffmpeg.ffprobe(filePath, (err, metadata) => {
      if (err) {
        reject(new Error(`Failed to probe video: ${err.message}`));
        return;
      }

      const videoStream = metadata.streams.find(s => s.codec_type === 'video');
      if (!videoStream) {
        reject(new Error('No video stream found in file'));
        return;
      }

      const duration = metadata.format.duration || 0;
      const width = videoStream.width || 0;
      const height = videoStream.height || 0;
      const codec = videoStream.codec_name || 'unknown';
      const bitrate = metadata.format.bit_rate
        ? parseInt(String(metadata.format.bit_rate), 10)
        : undefined;

      // Calculate FPS from frame rate string (e.g., "30/1" or "29.97")
      let fps: number | undefined;
      if (videoStream.r_frame_rate) {
        const [num, den] = videoStream.r_frame_rate.split('/').map(Number);
        fps = den ? num / den : num;
      }

      resolve({
        duration,
        width,
        height,
        codec,
        bitrate,
        fps,
      });
    });
  });
}

/**
 * Validate video meets requirements
 */
export function validateVideo(metadata: VideoMetadata): { valid: boolean; error?: string } {
  // Check duration
  if (metadata.duration > MAX_DURATION_SECONDS) {
    return {
      valid: false,
      error: `Video duration (${Math.ceil(metadata.duration)}s) exceeds maximum allowed (${MAX_DURATION_SECONDS}s)`,
    };
  }

  // Check codec is supported
  const codecLower = metadata.codec.toLowerCase();
  const isCodecSupported = SUPPORTED_CODECS.some(c => codecLower.includes(c));
  if (!isCodecSupported) {
    return {
      valid: false,
      error: `Unsupported video codec: ${metadata.codec}. Supported codecs: ${SUPPORTED_CODECS.join(', ')}`,
    };
  }

  return { valid: true };
}

/**
 * Generate a thumbnail from the video
 */
export async function generateThumbnail(
  videoPath: string,
  outputDir: string,
  timestampSeconds: number = 0.5
): Promise<string> {
  const thumbnailFilename = `thumb_${uuidv4()}.jpg`;
  const thumbnailPath = path.join(outputDir, thumbnailFilename);

  return new Promise((resolve, reject) => {
    ffmpeg(videoPath)
      .screenshots({
        timestamps: [timestampSeconds],
        filename: thumbnailFilename,
        folder: outputDir,
        size: `${THUMBNAIL_MAX_WIDTH}x?`, // Width constrained, height auto
      })
      .on('end', () => resolve(thumbnailPath))
      .on('error', (err) => reject(new Error(`Failed to generate thumbnail: ${err.message}`)));
  });
}

/**
 * Compress/resize video if needed
 */
export async function compressVideo(
  inputPath: string,
  outputDir: string,
  metadata: VideoMetadata
): Promise<{ outputPath: string; wasCompressed: boolean }> {
  // Check if compression is needed
  const needsResize = metadata.width > MAX_WIDTH || metadata.height > MAX_HEIGHT;
  const needsReencode = !metadata.codec.toLowerCase().includes('h264');
  const bitrateHigh = metadata.bitrate && metadata.bitrate > 8000000; // 8 Mbps threshold

  if (!needsResize && !needsReencode && !bitrateHigh) {
    // No processing needed, return original path
    return { outputPath: inputPath, wasCompressed: false };
  }

  const outputFilename = `video_${uuidv4()}.mp4`;
  const outputPath = path.join(outputDir, outputFilename);

  return new Promise((resolve, reject) => {
    let command = ffmpeg(inputPath)
      .outputOptions([
        '-c:v libx264',       // H.264 codec
        '-preset fast',       // Fast encoding
        '-crf 23',            // Quality level (18-28, lower is better)
        '-c:a aac',           // AAC audio
        '-b:a 128k',          // Audio bitrate
        '-movflags +faststart', // Enable streaming
        '-pix_fmt yuv420p',   // Compatibility
      ]);

    // Apply resize if needed
    if (needsResize) {
      // Calculate new dimensions maintaining aspect ratio
      const scale = Math.min(MAX_WIDTH / metadata.width, MAX_HEIGHT / metadata.height);
      const newWidth = Math.round(metadata.width * scale / 2) * 2; // Ensure even number
      const newHeight = Math.round(metadata.height * scale / 2) * 2;
      command = command.size(`${newWidth}x${newHeight}`);
    }

    command
      .output(outputPath)
      .on('end', () => resolve({ outputPath, wasCompressed: true }))
      .on('error', (err) => reject(new Error(`Failed to compress video: ${err.message}`)));

    command.run();
  });
}

/**
 * Process a video file: validate, generate thumbnail, compress if needed
 */
export async function processVideo(fileBuffer: Buffer, mimeType: string): Promise<VideoProcessingResult> {
  if (!ffmpegAvailable) {
    throw new Error('Video processing is not available. FFmpeg is not installed.');
  }

  // Create temp directory for processing
  const tempDir = path.join(os.tmpdir(), `video_processing_${uuidv4()}`);
  await fs.mkdir(tempDir, { recursive: true });

  const inputFilename = `input_${uuidv4()}${getExtensionFromMimeType(mimeType)}`;
  const inputPath = path.join(tempDir, inputFilename);

  try {
    // Write buffer to temp file
    await fs.writeFile(inputPath, fileBuffer);

    // Probe video metadata
    const metadata = await probeVideo(inputPath);

    // Validate video
    const validation = validateVideo(metadata);
    if (!validation.valid) {
      throw new Error(validation.error);
    }

    // Generate thumbnail
    const thumbnailPath = await generateThumbnail(inputPath, tempDir);

    // Compress if needed
    const { outputPath: processedVideoPath, wasCompressed } = await compressVideo(
      inputPath,
      tempDir,
      metadata
    );

    return {
      processedVideoPath,
      thumbnailPath,
      metadata,
      wasCompressed,
    };
  } catch (error) {
    // Clean up temp directory on error
    await cleanupTempDir(tempDir);
    throw error;
  }
}

/**
 * Read processed file as buffer
 */
export async function readFileAsBuffer(filePath: string): Promise<Buffer> {
  return fs.readFile(filePath);
}

/**
 * Clean up temporary processing directory
 */
export async function cleanupTempDir(tempDir: string): Promise<void> {
  try {
    const files = await fs.readdir(tempDir);
    for (const file of files) {
      await fs.unlink(path.join(tempDir, file));
    }
    await fs.rmdir(tempDir);
  } catch {
    // Ignore cleanup errors
  }
}

/**
 * Get file extension from MIME type
 */
function getExtensionFromMimeType(mimeType: string): string {
  const mimeToExt: Record<string, string> = {
    'video/mp4': '.mp4',
    'video/quicktime': '.mov',
    'video/webm': '.webm',
    'video/x-msvideo': '.avi',
    'video/x-matroska': '.mkv',
    'video/mpeg': '.mpeg',
    'video/3gpp': '.3gp',
    'video/x-m4v': '.m4v',
  };
  return mimeToExt[mimeType] || '.mp4';
}
