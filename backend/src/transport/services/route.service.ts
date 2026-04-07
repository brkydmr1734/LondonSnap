import { dataCache } from '../../common/utils/cache';
import { logger } from '../../common/utils/logger';

// ── Mapbox config ──
const MAPBOX_TOKEN = process.env.MAPBOX_TOKEN || 'pk.eyJ1IjoiYmVrbzE3IiwiYSI6ImNtbjZyNXE4NzA4aXcycHNjaWlrOGV2NTYifQ.dRfHY1VmnwGZ1QB4GL5Uuw';
const MAPBOX_DIRECTIONS_URL = 'https://api.mapbox.com/directions/v5/mapbox';

// Tube line colors (TfL official)
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
  'thameslink': '#D799AF',
};

// ── Output interfaces ──
export interface RouteLeg {
  mode: string;
  duration: number;       // minutes
  distance: number;       // meters
  instruction: string;
  departurePoint: string;
  arrivalPoint: string;
  path: { lat: number; lng: number }[];
  lineId?: string;
  lineName?: string;
  lineColor?: string;
  stops?: number;         // number of stops on this leg
  direction?: string;     // direction/destination of the line
}

export interface RouteOption {
  mode: string;           // 'walking' | 'bus' | 'tube' | 'driving' | 'mixed'
  duration: number;       // minutes
  distance: number;       // meters
  departureTime: string;
  arrivalTime: string;
  legs: RouteLeg[];
  polylinePoints: { lat: number; lng: number }[];
  fare?: string;          // estimated fare string
  co2?: number;           // CO2 in grams
  calories?: number;      // calories burned (walking/cycling)
  stopsCount?: number;    // total stops for transit routes
}

export interface NearbyStop {
  id: string;
  name: string;
  stopType: string;
  lat: number;
  lng: number;
  distance: number;
  lines: string[];
}

// ── TfL API types ──
interface TflJourneyLeg {
  duration: number;
  instruction: { summary: string; detailed?: string };
  departurePoint: { commonName: string; lat: number; lon: number };
  arrivalPoint: { commonName: string; lat: number; lon: number };
  mode: { id: string; name: string };
  routeOptions?: { lineIdentifier?: { id: string; name: string }; direction?: string }[];
  path?: { lineString: string };
  distance?: number;
  plannedWorks?: any[];
  isDisrupted?: boolean;
}

interface TflJourney {
  duration: number;
  startDateTime: string;
  arrivalDateTime: string;
  legs: TflJourneyLeg[];
  fare?: { totalCost: number; fares: { lowZone: number; highZone: number; cost: number; }[] };
}

interface TflJourneyResponse {
  journeys?: TflJourney[];
}

interface TflStopPoint {
  id: string;
  commonName: string;
  stopType: string;
  lat: number;
  lon: number;
  distance: number;
  lines?: { id: string; name: string }[];
}

interface TflStopPointResponse {
  stopPoints?: TflStopPoint[];
}

// ── Mapbox Directions types ──
interface MapboxStep {
  distance: number;
  duration: number;
  geometry: { coordinates: number[][] };
  maneuver: { instruction: string; type: string; modifier?: string };
  name: string;
}

interface MapboxLeg {
  distance: number;
  duration: number;
  steps: MapboxStep[];
  summary: string;
}

interface MapboxRoute {
  distance: number;  // meters
  duration: number;  // seconds
  geometry: { coordinates: number[][] };
  legs: MapboxLeg[];
}

interface MapboxDirectionsResponse {
  routes?: MapboxRoute[];
  code?: string;
}

// ── Supported transport modes ──
export type TransportMode = 'walking' | 'bus' | 'tube' | 'driving' | 'mixed';

// Cache TTLs
const ROUTE_CACHE_TTL_MS = 5 * 60 * 1000;  // 5 minutes
const STOPS_CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutes

class RouteService {
  private readonly journeyApiUrl = 'https://api.tfl.gov.uk/Journey/JourneyResults';
  private readonly stopPointApiUrl = 'https://api.tfl.gov.uk/StopPoint';

  /**
   * Get route options between two coordinates, filtered by transport mode.
   * - walking/driving: Mapbox Directions API (real polylines, distances)
   * - bus/tube: TfL Journey Planner API (live transit data)
   * - mixed: TfL with all modes
   */
  async getRouteOptions(
    fromLat: number,
    fromLng: number,
    toLat: number,
    toLng: number,
    mode: TransportMode = 'mixed'
  ): Promise<RouteOption[]> {
    const cacheKey = `route:${mode}:${fromLat.toFixed(4)},${fromLng.toFixed(4)}:${toLat.toFixed(4)},${toLng.toFixed(4)}`;

    const cached = dataCache.get<RouteOption[]>(cacheKey);
    if (cached) return cached;

    try {
      let routes: RouteOption[];

      switch (mode) {
        case 'walking':
          routes = await this.getMapboxRoutes(fromLat, fromLng, toLat, toLng, 'walking');
          break;
        case 'driving':
          routes = await this.getMapboxRoutes(fromLat, fromLng, toLat, toLng, 'driving');
          break;
        case 'bus':
          routes = await this.getTflRoutes(fromLat, fromLng, toLat, toLng, 'bus');
          break;
        case 'tube':
          routes = await this.getTflRoutes(fromLat, fromLng, toLat, toLng, 'tube');
          break;
        case 'mixed':
        default:
          routes = await this.getAllRoutes(fromLat, fromLng, toLat, toLng);
          break;
      }

      dataCache.set(cacheKey, routes, ROUTE_CACHE_TTL_MS);
      return routes;
    } catch (error) {
      logger.error(`Failed to fetch ${mode} routes:`, error);
      const fallback = dataCache.get<RouteOption[]>(cacheKey);
      return fallback || [];
    }
  }

  /**
   * Get all route types: Mapbox walking + driving + TfL bus + tube
   */
  private async getAllRoutes(
    fromLat: number, fromLng: number,
    toLat: number, toLng: number
  ): Promise<RouteOption[]> {
    const [walking, driving, tflRoutes] = await Promise.allSettled([
      this.getMapboxRoutes(fromLat, fromLng, toLat, toLng, 'walking'),
      this.getMapboxRoutes(fromLat, fromLng, toLat, toLng, 'driving'),
      this.getTflRoutes(fromLat, fromLng, toLat, toLng, 'bus,tube'),
    ]);

    const routes: RouteOption[] = [];

    if (walking.status === 'fulfilled') routes.push(...walking.value.slice(0, 1));
    if (driving.status === 'fulfilled') routes.push(...driving.value.slice(0, 1));
    if (tflRoutes.status === 'fulfilled') routes.push(...tflRoutes.value.slice(0, 3));

    return routes.sort((a, b) => a.duration - b.duration);
  }

  // ────────────────────────────────────────────
  // MAPBOX DIRECTIONS (walking + driving)
  // ────────────────────────────────────────────

  private async getMapboxRoutes(
    fromLat: number, fromLng: number,
    toLat: number, toLng: number,
    profile: 'walking' | 'driving'
  ): Promise<RouteOption[]> {
    try {
      const url = `${MAPBOX_DIRECTIONS_URL}/${profile}/${fromLng},${fromLat};${toLng},${toLat}`
        + `?access_token=${MAPBOX_TOKEN}`
        + `&geometries=geojson`
        + `&overview=full`
        + `&steps=true`
        + `&alternatives=true`
        + `&language=en`;

      const response = await fetch(url, {
        headers: { 'Accept': 'application/json' },
      });

      if (!response.ok) {
        throw new Error(`Mapbox API returned ${response.status}: ${response.statusText}`);
      }

      const data = await response.json() as MapboxDirectionsResponse;

      if (!data.routes || data.routes.length === 0) return [];

      const now = new Date();

      return data.routes.slice(0, 3).map((route) => {
        const durationMinutes = Math.round(route.duration / 60);
        const distanceMeters = Math.round(route.distance);
        const arrival = new Date(now.getTime() + route.duration * 1000);

        // Parse legs & steps into our format
        const legs = this.parseMapboxLegs(route, profile);

        // Full polyline from geometry
        const polylinePoints = route.geometry.coordinates.map(([lng, lat]) => ({
          lat, lng,
        }));

        // Estimates
        const calories = profile === 'walking'
          ? Math.round(durationMinutes * 4.5)  // ~4.5 cal/min walking
          : undefined;
        const co2 = profile === 'driving'
          ? Math.round(distanceMeters * 0.21)  // ~210g CO2/km for average car
          : 0;

        return {
          mode: profile,
          duration: durationMinutes,
          distance: distanceMeters,
          departureTime: now.toISOString(),
          arrivalTime: arrival.toISOString(),
          legs,
          polylinePoints,
          calories,
          co2,
        };
      });
    } catch (error) {
      logger.error(`Mapbox ${profile} directions failed:`, error);
      return [];
    }
  }

  private parseMapboxLegs(route: MapboxRoute, profile: string): RouteLeg[] {
    if (!route.legs || route.legs.length === 0) {
      return [{
        mode: profile,
        duration: Math.round(route.duration / 60),
        distance: Math.round(route.distance),
        instruction: profile === 'walking' ? 'Walk to destination' : 'Drive to destination',
        departurePoint: 'Start',
        arrivalPoint: 'Destination',
        path: route.geometry.coordinates.map(([lng, lat]) => ({ lat, lng })),
      }];
    }

    return route.legs.flatMap((leg) => {
      if (!leg.steps || leg.steps.length === 0) {
        return [{
          mode: profile,
          duration: Math.round(leg.duration / 60),
          distance: Math.round(leg.distance),
          instruction: leg.summary || `${profile === 'walking' ? 'Walk' : 'Drive'} to destination`,
          departurePoint: 'Start',
          arrivalPoint: 'Destination',
          path: route.geometry.coordinates.map(([lng, lat]) => ({ lat, lng })),
        }];
      }

      // Group steps into meaningful legs (combine very short steps)
      const grouped: RouteLeg[] = [];
      let currentLeg: RouteLeg | null = null;

      for (const step of leg.steps) {
        if (step.distance < 10) continue; // Skip tiny steps

        if (!currentLeg || step.maneuver.type === 'depart' || step.maneuver.type === 'arrive') {
          if (currentLeg) grouped.push(currentLeg);
          currentLeg = {
            mode: profile,
            duration: Math.round(step.duration / 60),
            distance: Math.round(step.distance),
            instruction: step.maneuver.instruction,
            departurePoint: step.name || 'Continue',
            arrivalPoint: step.name || 'Continue',
            path: step.geometry.coordinates.map(([lng, lat]) => ({ lat, lng })),
          };
        } else {
          // Merge into current leg
          currentLeg.duration += Math.round(step.duration / 60);
          currentLeg.distance += Math.round(step.distance);
          currentLeg.arrivalPoint = step.name || currentLeg.arrivalPoint;
          currentLeg.instruction = step.maneuver.instruction;
          currentLeg.path.push(
            ...step.geometry.coordinates.map(([lng, lat]) => ({ lat, lng }))
          );
        }
      }
      if (currentLeg) grouped.push(currentLeg);

      return grouped;
    });
  }

  // ────────────────────────────────────────────
  // TFL JOURNEY PLANNER (bus + tube)
  // ────────────────────────────────────────────

  private async getTflRoutes(
    fromLat: number, fromLng: number,
    toLat: number, toLng: number,
    tflMode: string
  ): Promise<RouteOption[]> {
    try {
      // TfL mode string: can be "bus", "tube", "bus,tube", etc.
      // Always include walking for connecting legs
      const modeParam = tflMode.includes(',') ? tflMode : `${tflMode},walking`;

      const url = `${this.journeyApiUrl}/${fromLat},${fromLng}/to/${toLat},${toLng}`
        + `?mode=${modeParam}`
        + `&journeyPreference=leasttime`
        + `&walkingSpeed=average`
        + `&cyclePreference=none`
        + `&adjustment=tripFirst`
        + `&alternativeWalking=false`;

      const response = await fetch(url, {
        headers: { 'Accept': 'application/json' },
      });

      if (!response.ok) {
        throw new Error(`TfL API returned ${response.status}: ${response.statusText}`);
      }

      const data = await response.json() as TflJourneyResponse;
      return this.parseTflJourneyResponse(data, tflMode);
    } catch (error) {
      logger.error(`TfL ${tflMode} routes failed:`, error);
      return [];
    }
  }

  private parseTflJourneyResponse(data: TflJourneyResponse, requestedMode: string): RouteOption[] {
    if (!data.journeys || data.journeys.length === 0) return [];

    return data.journeys
      .slice(0, 5) // Up to 5 options
      .map((journey) => {
        const legs = this.parseTflLegs(journey.legs);
        const polylinePoints = this.flattenPaths(legs);
        const mode = this.determineOverallMode(legs, requestedMode);
        const totalDistance = legs.reduce((sum, leg) => sum + leg.distance, 0);
        const totalStops = legs.reduce((sum, leg) => sum + (leg.stops || 0), 0);

        // Fare info
        let fare: string | undefined;
        if (journey.fare) {
          const totalPence = journey.fare.totalCost;
          fare = `£${(totalPence / 100).toFixed(2)}`;
        }

        // CO2 estimate for transit (~50g/km for bus, ~30g/km for tube)
        const transitKm = totalDistance / 1000;
        const co2 = Math.round(
          mode === 'bus' ? transitKm * 50 :
          mode === 'tube' ? transitKm * 30 :
          transitKm * 40
        );

        return {
          mode,
          duration: journey.duration,
          distance: totalDistance,
          departureTime: journey.startDateTime,
          arrivalTime: journey.arrivalDateTime,
          legs,
          polylinePoints,
          fare,
          co2,
          stopsCount: totalStops > 0 ? totalStops : undefined,
        };
      })
      .sort((a, b) => a.duration - b.duration);
  }

  private parseTflLegs(tflLegs: TflJourneyLeg[]): RouteLeg[] {
    return tflLegs.map((leg) => {
      const lineInfo = leg.routeOptions?.[0]?.lineIdentifier;
      const lineId = lineInfo?.id?.toLowerCase();
      const direction = leg.routeOptions?.[0]?.direction;

      const path = this.parseLineString(leg.path?.lineString);

      // Estimate distance from path if not provided
      let distance = leg.distance || 0;
      if (distance === 0 && path.length >= 2) {
        distance = this.estimatePathDistance(path);
      }

      return {
        mode: leg.mode.id,
        duration: leg.duration,
        distance: Math.round(distance),
        instruction: leg.instruction.summary,
        departurePoint: leg.departurePoint.commonName,
        arrivalPoint: leg.arrivalPoint.commonName,
        path,
        lineId: lineInfo?.id,
        lineName: lineInfo?.name,
        lineColor: lineId ? TUBE_LINE_COLORS[lineId] : undefined,
        direction: direction || undefined,
      };
    });
  }

  private parseLineString(lineString?: string): { lat: number; lng: number }[] {
    if (!lineString) return [];
    try {
      const coords = JSON.parse(lineString) as number[][];
      return coords.map(([lng, lat]) => ({ lat, lng }));
    } catch {
      return [];
    }
  }

  private flattenPaths(legs: RouteLeg[]): { lat: number; lng: number }[] {
    return legs.flatMap((leg) => leg.path);
  }

  private determineOverallMode(legs: RouteLeg[], requestedMode?: string): string {
    // Filter out walking legs for mode determination
    const transitLegs = legs.filter(l => l.mode !== 'walking');

    if (transitLegs.length === 0) return 'walking';

    const modes = new Set(transitLegs.map(l => l.mode));

    if (modes.size === 1) {
      const m = transitLegs[0]?.mode;
      if (m === 'bus') return 'bus';
      if (m === 'tube') return 'tube';
    }

    // If we explicitly requested a mode, prefer that label
    if (requestedMode === 'bus' && modes.has('bus')) return 'bus';
    if (requestedMode === 'tube' && modes.has('tube')) return 'tube';

    if (modes.has('tube') && !modes.has('bus')) return 'tube';
    if (modes.has('bus') && !modes.has('tube')) return 'bus';

    return 'mixed';
  }

  // ── Distance estimation from path ──
  private estimatePathDistance(path: { lat: number; lng: number }[]): number {
    let total = 0;
    for (let i = 1; i < path.length; i++) {
      total += this.haversine(
        path[i - 1].lat, path[i - 1].lng,
        path[i].lat, path[i].lng
      );
    }
    return total;
  }

  private haversine(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371000;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  // ────────────────────────────────────────────
  // NEARBY STOPS
  // ────────────────────────────────────────────

  async getNearbyStops(lat: number, lng: number, radius: number = 500): Promise<NearbyStop[]> {
    const cacheKey = `stops:${lat.toFixed(4)},${lng.toFixed(4)}:${radius}`;
    const cached = dataCache.get<NearbyStop[]>(cacheKey);
    if (cached) return cached;

    try {
      const url = `${this.stopPointApiUrl}?lat=${lat}&lon=${lng}&stopTypes=NaptanMetroStation,NaptanPublicBusCoachTram,NaptanRailStation&radius=${radius}`;

      const response = await fetch(url, {
        headers: { 'Accept': 'application/json' },
      });

      if (!response.ok) {
        throw new Error(`TfL API returned ${response.status}: ${response.statusText}`);
      }

      const data = await response.json() as TflStopPointResponse;
      const stops = this.parseStopPointResponse(data);

      dataCache.set(cacheKey, stops, STOPS_CACHE_TTL_MS);
      return stops;
    } catch (error) {
      logger.error('Failed to fetch nearby stops from TfL:', error);
      const fallback = dataCache.get<NearbyStop[]>(cacheKey);
      return fallback || [];
    }
  }

  private parseStopPointResponse(data: TflStopPointResponse): NearbyStop[] {
    if (!data.stopPoints || data.stopPoints.length === 0) return [];

    return data.stopPoints
      .map((stop) => ({
        id: stop.id,
        name: stop.commonName,
        stopType: this.mapStopType(stop.stopType),
        lat: stop.lat,
        lng: stop.lon,
        distance: stop.distance,
        lines: stop.lines?.map((line) => line.name) || [],
      }))
      .sort((a, b) => a.distance - b.distance)
      .slice(0, 10);
  }

  private mapStopType(stopType: string): string {
    if (stopType === 'NaptanMetroStation') return 'tube';
    if (stopType === 'NaptanPublicBusCoachTram') return 'bus';
    if (stopType.includes('Rail')) return 'rail';
    return 'other';
  }

  // ────────────────────────────────────────────
  // WALKING ROUTE (for Safety Walk matching)
  // ────────────────────────────────────────────

  async getWalkingRoute(
    fromLat: number, fromLng: number,
    toLat: number, toLng: number
  ): Promise<RouteOption | null> {
    const cacheKey = `walk:${fromLat.toFixed(4)},${fromLng.toFixed(4)}:${toLat.toFixed(4)},${toLng.toFixed(4)}`;
    const cached = dataCache.get<RouteOption>(cacheKey);
    if (cached) return cached;

    try {
      const routes = await this.getMapboxRoutes(fromLat, fromLng, toLat, toLng, 'walking');
      if (routes.length === 0) return null;

      const walkingRoute = routes[0];
      dataCache.set(cacheKey, walkingRoute, ROUTE_CACHE_TTL_MS);
      return walkingRoute;
    } catch (error) {
      logger.error('Failed to fetch walking route:', error);
      return dataCache.get<RouteOption>(cacheKey) || null;
    }
  }
}

export const routeService = new RouteService();
