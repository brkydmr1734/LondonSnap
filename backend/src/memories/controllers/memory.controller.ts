import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import dayjs from 'dayjs';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { prisma } from '../../index';
import { BadRequestError, NotFoundError, ForbiddenError } from '../../common/utils/AppError';

const JWT_SECRET = process.env.JWT_SECRET || 'secret';

// Validation schemas
const createMemorySchema = z.object({
  mediaUrl: z.string().url(),
  mediaType: z.enum(['IMAGE', 'VIDEO']),
  thumbnailUrl: z.string().url().optional(),
  caption: z.string().max(500).optional(),
  location: z.string().max(200).optional(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  originalSnapId: z.string().uuid().optional(),
  originalStoryId: z.string().uuid().optional(),
  albumId: z.string().uuid().optional(),
});

const createAlbumSchema = z.object({
  name: z.string().min(1).max(100),
  coverUrl: z.string().url().optional(),
  isPrivate: z.boolean().optional(),
});

const updateAlbumSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  coverUrl: z.string().url().nullable().optional(),
  isPrivate: z.boolean().optional(),
});

const updateMemorySchema = z.object({
  caption: z.string().max(500).nullable().optional(),
  albumId: z.string().uuid().nullable().optional(),
});

const paginationSchema = z.object({
  limit: z.coerce.number().min(1).max(100).default(50),
  offset: z.coerce.number().min(0).default(0),
});

// Vault schemas
const setupPinSchema = z.object({
  pin: z.string().regex(/^\d{4}$/, 'PIN must be exactly 4 digits'),
});

const verifyPinSchema = z.object({
  pin: z.string().regex(/^\d{4}$/, 'PIN must be exactly 4 digits'),
});

const changePinSchema = z.object({
  currentPin: z.string().regex(/^\d{4}$/, 'Current PIN must be exactly 4 digits'),
  newPin: z.string().regex(/^\d{4}$/, 'New PIN must be exactly 4 digits'),
});

export class MemoryController {
  // GET /api/v1/memories — list user's memories (paginated)
  async getMemories(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { limit, offset } = paginationSchema.parse(req.query);

      const [memories, total] = await Promise.all([
        prisma.memory.findMany({
          where: { userId: req.user.id, isMyEyesOnly: false },
          include: {
            album: {
              select: {
                id: true,
                name: true,
                coverUrl: true,
              },
            },
          },
          orderBy: { takenAt: 'desc' },
          take: limit,
          skip: offset,
        }),
        prisma.memory.count({
          where: { userId: req.user.id, isMyEyesOnly: false },
        }),
      ]);

      res.json({
        success: true,
        data: {
          memories,
          pagination: {
            total,
            limit,
            offset,
            hasMore: offset + memories.length < total,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  }

  // GET /api/v1/memories/albums — list user's albums with memory count
  async getAlbums(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const albums = await prisma.memoryAlbum.findMany({
        where: { userId: req.user.id },
        include: {
          _count: {
            select: { memories: true },
          },
        },
        orderBy: { updatedAt: 'desc' },
      });

      // Transform to include memoryCount at top level
      const albumsWithCount = albums.map(album => ({
        id: album.id,
        name: album.name,
        coverUrl: album.coverUrl,
        isPrivate: album.isPrivate,
        createdAt: album.createdAt,
        updatedAt: album.updatedAt,
        memoryCount: album._count.memories,
      }));

      res.json({
        success: true,
        data: { albums: albumsWithCount },
      });
    } catch (error) {
      next(error);
    }
  }

  // POST /api/v1/memories — save to memories
  async createMemory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const data = createMemorySchema.parse(req.body);

      // Verify album ownership if albumId provided
      if (data.albumId) {
        const album = await prisma.memoryAlbum.findFirst({
          where: {
            id: data.albumId,
            userId: req.user.id,
          },
        });

        if (!album) {
          throw new NotFoundError('Album not found');
        }
      }

      const memory = await prisma.memory.create({
        data: {
          userId: req.user.id,
          mediaUrl: data.mediaUrl,
          mediaType: data.mediaType,
          thumbnailUrl: data.thumbnailUrl,
          caption: data.caption,
          location: data.location,
          latitude: data.latitude,
          longitude: data.longitude,
          originalSnapId: data.originalSnapId,
          originalStoryId: data.originalStoryId,
          albumId: data.albumId,
          takenAt: new Date(),
        },
        include: {
          album: {
            select: {
              id: true,
              name: true,
            },
          },
        },
      });

      res.status(201).json({
        success: true,
        message: 'Memory saved',
        data: { memory },
      });
    } catch (error) {
      next(error);
    }
  }

  // POST /api/v1/memories/albums — create album
  async createAlbum(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const data = createAlbumSchema.parse(req.body);

      const album = await prisma.memoryAlbum.create({
        data: {
          userId: req.user.id,
          name: data.name,
          coverUrl: data.coverUrl,
          isPrivate: data.isPrivate ?? true,
        },
      });

      res.status(201).json({
        success: true,
        message: 'Album created',
        data: { album },
      });
    } catch (error) {
      next(error);
    }
  }

  // PUT /api/v1/memories/albums/:id — update album
  async updateAlbum(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { id } = req.params;
      const data = updateAlbumSchema.parse(req.body);

      // Verify ownership
      const existingAlbum = await prisma.memoryAlbum.findFirst({
        where: {
          id,
          userId: req.user.id,
        },
      });

      if (!existingAlbum) {
        throw new NotFoundError('Album not found');
      }

      const album = await prisma.memoryAlbum.update({
        where: { id },
        data: {
          ...(data.name !== undefined && { name: data.name }),
          ...(data.coverUrl !== undefined && { coverUrl: data.coverUrl }),
          ...(data.isPrivate !== undefined && { isPrivate: data.isPrivate }),
        },
      });

      res.json({
        success: true,
        message: 'Album updated',
        data: { album },
      });
    } catch (error) {
      next(error);
    }
  }

  // DELETE /api/v1/memories/:id — delete memory
  async deleteMemory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { id } = req.params;

      // Verify ownership
      const memory = await prisma.memory.findFirst({
        where: {
          id,
          userId: req.user.id,
        },
      });

      if (!memory) {
        throw new NotFoundError('Memory not found');
      }

      await prisma.memory.delete({
        where: { id },
      });

      res.json({
        success: true,
        message: 'Memory deleted',
      });
    } catch (error) {
      next(error);
    }
  }

  // PATCH /api/v1/memories/:id — update memory
  async updateMemory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { id } = req.params;
      const data = updateMemorySchema.parse(req.body);

      // Verify ownership
      const existingMemory = await prisma.memory.findFirst({
        where: {
          id,
          userId: req.user.id,
        },
      });

      if (!existingMemory) {
        throw new NotFoundError('Memory not found');
      }

      // Verify album ownership if albumId provided
      if (data.albumId) {
        const album = await prisma.memoryAlbum.findFirst({
          where: {
            id: data.albumId,
            userId: req.user.id,
          },
        });

        if (!album) {
          throw new NotFoundError('Album not found');
        }
      }

      const memory = await prisma.memory.update({
        where: { id },
        data: {
          ...(data.caption !== undefined && { caption: data.caption }),
          ...(data.albumId !== undefined && { albumId: data.albumId }),
        },
        include: {
          album: {
            select: {
              id: true,
              name: true,
              coverUrl: true,
            },
          },
        },
      });

      res.json({
        success: true,
        message: 'Memory updated',
        data: { memory },
      });
    } catch (error) {
      next(error);
    }
  }

  // POST /api/v1/memories/:id/reshare — re-share as story
  async reshareAsStory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { id } = req.params;

      // Find the memory and verify ownership
      const memory = await prisma.memory.findFirst({
        where: {
          id,
          userId: req.user.id,
        },
      });

      if (!memory) {
        throw new NotFoundError('Memory not found');
      }

      // Create a new story from the memory's media
      const story = await prisma.story.create({
        data: {
          userId: req.user.id,
          mediaUrl: memory.mediaUrl,
          mediaType: memory.mediaType,
          thumbnailUrl: memory.thumbnailUrl,
          caption: memory.caption,
          location: memory.location,
          latitude: memory.latitude,
          longitude: memory.longitude,
          privacy: 'FRIENDS',
          allowReplies: true,
          expiresAt: dayjs().add(24, 'hours').toDate(),
        },
        include: {
          user: {
            select: {
              id: true,
              username: true,
              displayName: true,
              avatarUrl: true,
              avatarConfig: true,
            },
          },
        },
      });

      res.status(201).json({
        success: true,
        message: 'Memory reshared as story',
        data: { story },
      });
    } catch (error) {
      next(error);
    }
  }

  // ========================================
  // MY EYES ONLY VAULT ENDPOINTS
  // ========================================

  // GET /api/v1/memories/my-eyes-only/status — check vault status
  async getVaultStatus(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const vault = await prisma.myEyesOnlyVault.findUnique({
        where: { userId: req.user.id },
      });

      const now = new Date();
      const isLocked = vault?.lockedUntil ? vault.lockedUntil > now : false;

      res.json({
        success: true,
        data: {
          hasVault: !!vault,
          isLocked,
          failedAttempts: vault?.failedAttempts ?? 0,
          lockedUntil: isLocked ? vault?.lockedUntil : null,
        },
      });
    } catch (error) {
      next(error);
    }
  }

  // POST /api/v1/memories/my-eyes-only/setup — setup vault PIN
  async setupVault(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { pin } = setupPinSchema.parse(req.body);

      // Check if vault already exists
      const existing = await prisma.myEyesOnlyVault.findUnique({
        where: { userId: req.user.id },
      });

      if (existing) {
        throw new BadRequestError('Vault already exists. Use change-pin instead.');
      }

      const pinHash = await bcrypt.hash(pin, 10);

      await prisma.myEyesOnlyVault.create({
        data: {
          userId: req.user.id,
          pinHash,
        },
      });

      res.status(201).json({
        success: true,
        message: 'My Eyes Only vault created successfully',
      });
    } catch (error) {
      next(error);
    }
  }

  // POST /api/v1/memories/my-eyes-only/verify — verify PIN and get access token
  async verifyVault(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { pin } = verifyPinSchema.parse(req.body);

      const vault = await prisma.myEyesOnlyVault.findUnique({
        where: { userId: req.user.id },
      });

      if (!vault) {
        throw new NotFoundError('Vault not setup. Please create a PIN first.');
      }

      // Check lockout
      if (vault.lockedUntil && vault.lockedUntil > new Date()) {
        const remaining = Math.ceil((vault.lockedUntil.getTime() - Date.now()) / 60000);
        throw new ForbiddenError(`Vault locked. Try again in ${remaining} minute${remaining === 1 ? '' : 's'}.`);
      }

      const isValid = await bcrypt.compare(pin, vault.pinHash);

      if (!isValid) {
        const attempts = vault.failedAttempts + 1;
        const updateData: { failedAttempts: number; lockedUntil?: Date } = { failedAttempts: attempts };

        if (attempts >= 5) {
          updateData.lockedUntil = new Date(Date.now() + 30 * 60 * 1000); // 30 min lockout
        }

        await prisma.myEyesOnlyVault.update({
          where: { userId: req.user.id },
          data: updateData,
        });

        const remaining = 5 - attempts;
        if (remaining > 0) {
          throw new ForbiddenError(`Invalid PIN. ${remaining} attempt${remaining === 1 ? '' : 's'} remaining.`);
        } else {
          throw new ForbiddenError('Too many failed attempts. Vault locked for 30 minutes.');
        }
      }

      // Reset failed attempts on success
      await prisma.myEyesOnlyVault.update({
        where: { userId: req.user.id },
        data: { failedAttempts: 0, lockedUntil: null },
      });

      // Generate vault token (15 min TTL)
      const vaultToken = jwt.sign(
        { userId: req.user.id, type: 'vault_access' },
        JWT_SECRET,
        { expiresIn: '15m' }
      );

      res.json({
        success: true,
        message: 'Vault unlocked',
        data: {
          vaultToken,
          expiresIn: 900, // 900 seconds = 15 min
        },
      });
    } catch (error) {
      next(error);
    }
  }

  // POST /api/v1/memories/my-eyes-only/change-pin — change vault PIN
  async changeVaultPin(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { currentPin, newPin } = changePinSchema.parse(req.body);

      const vault = await prisma.myEyesOnlyVault.findUnique({
        where: { userId: req.user.id },
      });

      if (!vault) {
        throw new NotFoundError('Vault not setup');
      }

      // Check lockout
      if (vault.lockedUntil && vault.lockedUntil > new Date()) {
        const remaining = Math.ceil((vault.lockedUntil.getTime() - Date.now()) / 60000);
        throw new ForbiddenError(`Vault locked. Try again in ${remaining} minute${remaining === 1 ? '' : 's'}.`);
      }

      const isValid = await bcrypt.compare(currentPin, vault.pinHash);

      if (!isValid) {
        throw new ForbiddenError('Current PIN is incorrect');
      }

      const pinHash = await bcrypt.hash(newPin, 10);

      await prisma.myEyesOnlyVault.update({
        where: { userId: req.user.id },
        data: { pinHash, failedAttempts: 0, lockedUntil: null },
      });

      res.json({
        success: true,
        message: 'PIN changed successfully',
      });
    } catch (error) {
      next(error);
    }
  }

  // GET /api/v1/memories/my-eyes-only — get My Eyes Only memories (requires vault token)
  async getMyEyesOnlyMemories(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { limit, offset } = paginationSchema.parse(req.query);

      const [memories, total] = await Promise.all([
        prisma.memory.findMany({
          where: { userId: req.user.id, isMyEyesOnly: true },
          orderBy: { createdAt: 'desc' },
          take: limit,
          skip: offset,
        }),
        prisma.memory.count({
          where: { userId: req.user.id, isMyEyesOnly: true },
        }),
      ]);

      res.json({
        success: true,
        data: {
          memories,
          pagination: {
            total,
            limit,
            offset,
            hasMore: offset + memories.length < total,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  }

  // POST /api/v1/memories/:id/move-to-vault — move memory to vault
  async moveToVault(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { id } = req.params;

      const memory = await prisma.memory.findFirst({
        where: { id, userId: req.user.id },
      });

      if (!memory) {
        throw new NotFoundError('Memory not found');
      }

      if (memory.isMyEyesOnly) {
        throw new BadRequestError('Memory is already in My Eyes Only');
      }

      // Check if user has vault setup
      const vault = await prisma.myEyesOnlyVault.findUnique({
        where: { userId: req.user.id },
      });

      if (!vault) {
        throw new BadRequestError('Please set up My Eyes Only PIN first');
      }

      const updatedMemory = await prisma.memory.update({
        where: { id },
        data: {
          isMyEyesOnly: true,
          albumId: null, // Remove from albums when moving to vault
        },
      });

      res.json({
        success: true,
        message: 'Memory moved to My Eyes Only',
        data: { memory: updatedMemory },
      });
    } catch (error) {
      next(error);
    }
  }

  // POST /api/v1/memories/:id/move-from-vault — move memory from vault (requires vault token)
  async moveFromVault(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) {
        throw new BadRequestError('Authentication required');
      }

      const { id } = req.params;

      const memory = await prisma.memory.findFirst({
        where: { id, userId: req.user.id, isMyEyesOnly: true },
      });

      if (!memory) {
        throw new NotFoundError('Memory not found in vault');
      }

      const updatedMemory = await prisma.memory.update({
        where: { id },
        data: { isMyEyesOnly: false },
      });

      res.json({
        success: true,
        message: 'Memory moved from My Eyes Only',
        data: { memory: updatedMemory },
      });
    } catch (error) {
      next(error);
    }
  }
}

export const memoryController = new MemoryController();
