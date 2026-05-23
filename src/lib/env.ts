import { createEnv } from '@t3-oss/env-nextjs';
import { z } from 'zod';

/**
 * Strongly-typed, validated environment variables.
 *
 * - `server`:        accessible only on the server. Build fails if any are missing.
 * - `client`:        must start with `NEXT_PUBLIC_`. Exposed to the browser.
 * - `runtimeEnv`:    explicit mapping; `@t3-oss/env-nextjs` cannot read process.env
 *                    dynamically on the client. Every variable must be listed.
 *
 * Never import this module from purely-client code in a way that needs the
 * server section — the build will throw. Use the `client` section for anything
 * the browser legitimately needs.
 */
export const env = createEnv({
  server: {
    SUPABASE_SERVICE_ROLE_KEY: z.string().min(1).optional(),
    UPSTASH_REDIS_REST_URL: z.string().url().optional(),
    UPSTASH_REDIS_REST_TOKEN: z.string().min(1).optional(),
  },
  client: {
    NEXT_PUBLIC_APP_URL: z.string().url(),
    NEXT_PUBLIC_SUPABASE_URL: z.string().url().optional(),
    NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1).optional(),
  },
  runtimeEnv: {
    NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
    UPSTASH_REDIS_REST_URL: process.env.UPSTASH_REDIS_REST_URL,
    UPSTASH_REDIS_REST_TOKEN: process.env.UPSTASH_REDIS_REST_TOKEN,
  },
  // Treat empty strings as missing — common pitfall on Vercel.
  emptyStringAsUndefined: true,
  // Skip validation during lint / typegen so that incomplete CI environments
  // don't fail those steps. Real `dev`/`build` runs still validate.
  skipValidation: process.env.SKIP_ENV_VALIDATION === 'true',
});
