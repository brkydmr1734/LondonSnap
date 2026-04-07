import { dataCache } from '../../common/utils/cache';
import { logger } from '../../common/utils/logger';

// TfL API response types
interface TflLineStatus {
  id: string;
  name: string;
  lineStatuses: {
    statusSeverity: number;
    statusSeverityDescription: string;
    reason?: string;
  }[];
}

// Clean output format
export interface TubeLineStatus {
  id: string;          // e.g., "bakerloo"
  name: string;        // e.g., "Bakerloo"
  color: string;       // hex color, e.g., "#B36305"
  status: string;      // e.g., "Good Service", "Minor Delays"
  severity: number;    // TfL severity level (10 = good, 6 = severe delays, etc.)
  reason: string | null; // disruption reason if any
}

// Hardcoded tube line colors
const TUBE_LINE_COLORS: Record<string, string> = {
  'bakerloo': '#B36305',
  'central': '#E32017',
  'circle': '#FFD300',
  'district': '#00782A',
  'hammersmith-city': '#F3A9BB',
  'jubilee': '#A0A5A9',
  'metropolitan': '#9B0056',
  'northern': '#000000',
  'piccadilly': '#003688',
  'victoria': '#0098D4',
  'waterloo-city': '#95CDBA',
  'elizabeth': '#6950A1',
  'dlr': '#00A4A7',
  'london-overground': '#EE7C0E',
};

// Cache key and TTL
const CACHE_KEY = 'tube:status';
const CACHE_TTL_MS = 3 * 60 * 1000; // 3 minutes

class TflService {
  private readonly apiUrl = 'https://api.tfl.gov.uk/Line/Mode/tube/Status';

  /**
   * Fetch tube status from TfL API and cache the result
   */
  async fetchAndCacheStatus(): Promise<TubeLineStatus[]> {
    try {
      const response = await fetch(this.apiUrl, {
        headers: {
          'Accept': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`TfL API returned ${response.status}: ${response.statusText}`);
      }

      const data = await response.json() as TflLineStatus[];
      const statuses = this.parseResponse(data);

      // Cache the result
      dataCache.set(CACHE_KEY, statuses, CACHE_TTL_MS);

      return statuses;
    } catch (error) {
      logger.error('Failed to fetch TfL tube status:', error);
      
      // Return cached data if available, otherwise empty array
      const cached = dataCache.get<TubeLineStatus[]>(CACHE_KEY);
      if (cached) {
        logger.info('Returning cached tube status after fetch failure');
        return cached;
      }
      
      return [];
    }
  }

  /**
   * Get tube status from cache, or fetch if not cached
   */
  async getStatus(): Promise<TubeLineStatus[]> {
    const cached = dataCache.get<TubeLineStatus[]>(CACHE_KEY);
    if (cached) {
      return cached;
    }

    // Cache miss - fetch fresh data
    return this.fetchAndCacheStatus();
  }

  /**
   * Parse TfL API response into clean format
   */
  private parseResponse(data: TflLineStatus[]): TubeLineStatus[] {
    return data.map((line) => {
      // Get the first (most severe) status
      const status = line.lineStatuses[0];
      
      return {
        id: line.id,
        name: line.name,
        color: TUBE_LINE_COLORS[line.id] || '#808080', // Default gray if unknown
        status: status?.statusSeverityDescription || 'Unknown',
        severity: status?.statusSeverity || 0,
        reason: status?.reason || null,
      };
    }).sort((a, b) => {
      // Sort by severity (lower = worse) to show disruptions first
      return a.severity - b.severity;
    });
  }
}

export const tflService = new TflService();
