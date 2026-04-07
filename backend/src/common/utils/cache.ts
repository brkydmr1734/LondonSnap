/**
 * High-performance in-memory cache with TTL.
 * Used to eliminate redundant DB queries for auth, user profiles, etc.
 * No external dependency — pure Map-based with automatic cleanup.
 */

interface CacheEntry<T> {
  value: T;
  expiresAt: number;
}

export class MemoryCache {
  private store = new Map<string, CacheEntry<any>>();
  private cleanupInterval: NodeJS.Timeout;

  constructor(cleanupMs = 60_000) {
    // Periodic cleanup of expired entries
    this.cleanupInterval = setInterval(() => this.cleanup(), cleanupMs);
    // Don't keep the process alive just for cleanup
    this.cleanupInterval.unref();
  }

  get<T>(key: string): T | undefined {
    const entry = this.store.get(key);
    if (!entry) return undefined;
    if (Date.now() > entry.expiresAt) {
      this.store.delete(key);
      return undefined;
    }
    return entry.value as T;
  }

  set<T>(key: string, value: T, ttlMs: number): void {
    this.store.set(key, { value, expiresAt: Date.now() + ttlMs });
  }

  delete(key: string): void {
    this.store.delete(key);
  }

  /** Invalidate all keys matching a prefix (e.g., "user:abc") */
  invalidatePrefix(prefix: string): void {
    for (const key of this.store.keys()) {
      if (key.startsWith(prefix)) this.store.delete(key);
    }
  }

  get size(): number {
    return this.store.size;
  }

  private cleanup(): void {
    const now = Date.now();
    for (const [key, entry] of this.store) {
      if (now > entry.expiresAt) this.store.delete(key);
    }
  }

  destroy(): void {
    clearInterval(this.cleanupInterval);
    this.store.clear();
  }
}

// Singleton caches with different TTLs
/** Auth cache: user + session data. TTL = 30s (security-sensitive) */
export const authCache = new MemoryCache(30_000);

/** Data cache: profiles, friend lists, etc. TTL cleanup every 2 min */
export const dataCache = new MemoryCache(120_000);

// Cache TTL constants (in milliseconds)
export const CACHE_TTL = {
  AUTH_USER: 30_000,      // 30s — user object from auth middleware
  AUTH_SESSION: 30_000,   // 30s — session validation
  USER_PROFILE: 60_000,   // 1min — user profile data
  FRIENDS_LIST: 30_000,   // 30s — friend list
  CHAT_LIST: 15_000,      // 15s — chat list
  STORY_FEED: 20_000,     // 20s — story feed
} as const;
