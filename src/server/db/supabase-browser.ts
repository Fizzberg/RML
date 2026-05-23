import { createBrowserClient } from '@supabase/ssr';

import { env } from '@/lib/env';

/**
 * Browser-side Supabase client.
 *
 * Uses the anon key. RLS is the security boundary in this context; do not
 * trust any client-supplied user identity for authorisation decisions. Server
 * actions must re-check `auth.uid()` and roles server-side.
 *
 * This module is intentionally not marked `server-only` — it is the one
 * Supabase factory that runs in the browser bundle.
 */
export function createSupabaseBrowserClient() {
  if (!env.NEXT_PUBLIC_SUPABASE_URL || !env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    throw new Error(
      'Supabase environment variables are not configured. ' +
        'Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in .env.local.',
    );
  }

  return createBrowserClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
}
