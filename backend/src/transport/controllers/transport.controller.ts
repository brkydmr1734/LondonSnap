import { Request, Response, NextFunction } from 'express';
import { tflService } from '../services/tfl.service';
import { routeService, TransportMode } from '../services/route.service';

const VALID_MODES: TransportMode[] = ['walking', 'bus', 'tube', 'driving', 'mixed'];

class TransportController {
  /**
   * GET /tube-status
   * Returns cached tube line statuses
   */
  async getTubeStatus(req: Request, res: Response, next: NextFunction) {
    try {
      const statuses = await tflService.getStatus();

      res.json({
        success: true,
        data: {
          lines: statuses,
          updatedAt: new Date().toISOString(),
        },
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * GET /route
   * Returns route options between two coordinates.
   * Query params: fromLat, fromLng, toLat, toLng, mode (optional: walking|bus|tube|driving|mixed)
   */
  async getRouteOptions(req: Request, res: Response, next: NextFunction) {
    try {
      const { fromLat, fromLng, toLat, toLng, mode } = req.query;

      // Validate all params exist
      if (!fromLat || !fromLng || !toLat || !toLng) {
        return res.status(400).json({
          success: false,
          error: 'Missing required query parameters: fromLat, fromLng, toLat, toLng',
        });
      }

      // Validate params are valid numbers
      const coords = {
        fromLat: parseFloat(fromLat as string),
        fromLng: parseFloat(fromLng as string),
        toLat: parseFloat(toLat as string),
        toLng: parseFloat(toLng as string),
      };

      if (Object.values(coords).some(isNaN)) {
        return res.status(400).json({
          success: false,
          error: 'Invalid coordinates: all parameters must be valid numbers',
        });
      }

      // Validate mode if provided
      const transportMode: TransportMode = mode && VALID_MODES.includes(mode as TransportMode)
        ? (mode as TransportMode)
        : 'mixed';

      const routes = await routeService.getRouteOptions(
        coords.fromLat,
        coords.fromLng,
        coords.toLat,
        coords.toLng,
        transportMode
      );

      res.json({
        success: true,
        data: {
          routes,
          mode: transportMode,
        },
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * GET /nearby-stops
   * Returns nearby transport stops for a location
   */
  async getNearbyStops(req: Request, res: Response, next: NextFunction) {
    try {
      const { lat, lng, radius } = req.query;

      // Validate lat/lng exist
      if (!lat || !lng) {
        return res.status(400).json({
          success: false,
          error: 'Missing required query parameters: lat, lng',
        });
      }

      // Validate params are valid numbers
      const parsedLat = parseFloat(lat as string);
      const parsedLng = parseFloat(lng as string);
      const parsedRadius = radius ? parseInt(radius as string, 10) : 500;

      if (isNaN(parsedLat) || isNaN(parsedLng)) {
        return res.status(400).json({
          success: false,
          error: 'Invalid coordinates: lat and lng must be valid numbers',
        });
      }

      if (isNaN(parsedRadius) || parsedRadius < 1 || parsedRadius > 5000) {
        return res.status(400).json({
          success: false,
          error: 'Invalid radius: must be a number between 1 and 5000',
        });
      }

      const stops = await routeService.getNearbyStops(parsedLat, parsedLng, parsedRadius);

      res.json({
        success: true,
        data: {
          stops,
        },
      });
    } catch (error) {
      next(error);
    }
  }
}

export const transportController = new TransportController();
