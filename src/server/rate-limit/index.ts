import 'server-only';

import { Ratelimit } from '@upstash/ratelimit';
import { Redis } from '@upstash/redis';

import { env } from '@/lib/env';

/**
 * Single Upstash Redis client, used as the substrate for all rate limiters
 * (see `docs/SECURITY_RULES.md` §6 and `docs/PRODUCT_DECISIONS.md` §11).
 *
 * The client is `null` when the environment variables are absent — useful for
 * local development without Upstash configured. Production deploys must set
 * the variables; the limiter factory will refuse to create a limiter without
 * them.
 */
const redis =
  env.UPSTASH_REDIS_REST_URL && env.UPSTASH_REDIS_REST_TOKEN
    ? new Redis({
        url: env.UPSTASH_REDIS_REST_URL,
        token: env.UPSTASH_REDIS_REST_TOKEN,
      })
    : null;

export interface RateLimiterOptions {
  /** Unique identifier for this limiter, used as the Redis key prefix. */
  prefix: string;
  /** Number of allowed requests in the window. */
  limit: number;
  /** Window duration (e.g. `'10 s'`, `'1 m'`, `'1 h'`, `'1 d'`). */
  window: Parameters<typeof Ratelimit.slidingWindow>[1];
}

/**
 * Create a sliding-window rate limiter for a specific surface. Each call
 * returns a fresh `Ratelimit` instance bound to the shared Redis client.
 *
 * Surfaces that need rate limiting (auth, review submission, search, public
 * pages, signed-URL minting, reporting) each declare their own limiter via
 * this factory. Concrete limiters will live next to the feature that uses
 * them.
 */
export function createRateLimiter({ prefix, limit, window }: RateLimiterOptions): Ratelimit {
  if (!redis) {
    throw new Error(
      'Upstash Redis is not configured. ' +
        'Set UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN in .env.local.',
    );
  }

  return new Ratelimit({
    redis,
    limiter: Ratelimit.slidingWindow(limit, window),
    prefix: `rml:${prefix}`,
    analytics: true,
  });
}
