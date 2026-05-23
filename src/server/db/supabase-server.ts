import 'server-only';

import { cookies } from 'next/headers';

import { createServerClient, type CookieOptions } from '@supabase/ssr';

import { env } from '@/lib/env';

/**
 * Server-side Supabase client bound to the current request's cookies.
 *
 * Use this in server components, server actions, and route handlers when you
 * need to act in the user's session under RLS. Never use the service-role key
 * here — that lives in `supabase-admin.ts` and is only for genuinely
 * privileged code paths (see `docs/SECURITY_RULES.md` §2).
 *
 * NOTE: this is a scaffold. Concrete repositories and services will wrap this
 * factory; do not import it directly from UI components.
 */
export async function createSupabaseServerClient() {
  const cookieStore = await cookies();

  if (!env.NEXT_PUBLIC_SUPABASE_URL || !env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    throw new Error(
      'Supabase environment variables are not configured. ' +
        'Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in .env.local.',
    );
  }

  return createServerClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (cookiesToSet: { name: string; value: string; options: CookieOptions }[]) => {
        try {
          cookiesToSet.forEach(({ name, value, options }) => {
            cookieStore.set(name, value, options);
          });
        } catch {
          // Server components cannot set cookies; the middleware refreshes
          // sessions instead. Swallowing here is safe.
        }
      },
    },
  });
}
