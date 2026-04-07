import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { storyService } from '../services/story.service';
import { BadRequestError } from '../../common/utils/AppError';

const postStorySchema = z.object({
  mediaUrl: z.string().url(),
  mediaType: z.enum(['IMAGE', 'VIDEO']),
  thumbnailUrl: z.string().url().optional(),
  duration: z.number().positive().optional(),
  caption: z.string().max(200).optional(),
  drawingData: z.any().optional(),
  stickers: z.any().optional(),
  filters: z.any().optional(),
  location: z.string().max(100).optional(),
  latitude: z.number().optional(),
  longitude: z.number().optional(),
  privacy: z.enum(['EVERYONE', 'FRIENDS', 'CLOSE_FRIENDS', 'CUSTOM']).optional(),
  allowReplies: z.boolean().optional(),
  circleId: z.string().uuid().optional(),
});

export class StoryController {
  async postStory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      const data = postStorySchema.parse(req.body);
      const story = await storyService.postStory(req.user.id, data);

      res.status(201).json({
        success: true,
        message: 'Story posted',
        data: { story },
      });
    } catch (error) {
      next(error);
    }
  }

  async getStoriesFeed(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      const stories = await storyService.getStoriesFeed(req.user.id);

      res.json({
        success: true,
        data: { stories },
      });
    } catch (error) {
      next(error);
    }
  }

  async getMyStories(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      const stories = await storyService.getMyStories(req.user.id);

      res.json({
        success: true,
        data: { stories },
      });
    } catch (error) {
      next(error);
    }
  }

  async getUserStories(req: Request, res: Response, next: NextFunction) {
    try {
      const { userId } = req.params;
      const result = await storyService.getUserStories(userId, req.user?.id);

      res.json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  async viewStory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      const { storyId } = req.params;
      const story = await storyService.viewStory(req.user.id, storyId);

      res.json({
        success: true,
        data: { story },
      });
    } catch (error) {
      next(error);
    }
  }

  async getStoryViewers(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      const { storyId } = req.params;
      const viewers = await storyService.getStoryViewers(req.user.id, storyId);

      res.json({
        success: true,
        data: { viewers },
      });
    } catch (error) {
      next(error);
    }
  }

  async reactToStory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      const { storyId } = req.params;
      const { emoji } = req.body;

      if (!emoji) throw new BadRequestError('Emoji required');

      const reaction = await storyService.reactToStory(req.user.id, storyId, emoji);

      res.json({
        success: true,
        data: { reaction },
      });
    } catch (error) {
      next(error);
    }
  }

  async replyToStory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      const { storyId } = req.params;
      const { content } = req.body;

      if (!content) throw new BadRequestError('Reply content required');

      const result = await storyService.replyToStory(req.user.id, storyId, content);

      res.json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }

  async deleteStory(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      const { storyId } = req.params;
      await storyService.deleteStory(req.user.id, storyId);

      res.json({
        success: true,
        message: 'Story deleted',
      });
    } catch (error) {
      next(error);
    }
  }

  async updateStorySettings(req: Request, res: Response, next: NextFunction) {
    try {
      if (!req.user) throw new BadRequestError('Authentication required');

      const { storyId } = req.params;
      const { privacy, allowReplies } = req.body;

      const story = await storyService.updateStorySettings(req.user.id, storyId, {
        privacy,
        allowReplies,
      });

      res.json({
        success: true,
        data: { story },
      });
    } catch (error) {
      next(error);
    }
  }
}

export const storyController = new StoryController();
