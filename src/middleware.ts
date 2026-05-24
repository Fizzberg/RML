import type { NextRequest, NextResponse } from 'next/server';

import { createServerClient, type CookieOptions } from '@supabase/ssr';
import createIntlMiddleware from 'next-intl/middleware';

import { routing } from './i18n/routing';
import { env } from './lib/env';

const intlMiddleware = createIntlMiddleware(routing);

/**
 * Combined middleware:
 *   1. next-intl handles locale routing (default locale + `as-needed` prefix).
 *   2. Supabase SSR refreshes the auth cookies on each request so that server
 *      components downstream see a current session.
 *
 * The next-intl response object is used for both — when next-intl emits a
 * redirect (e.g. stripping or adding a locale prefix), the refreshed
 * cookies still ride along to the browser and are present on the redirected
 * follow-up request.
 *
 * If Supabase env vars are not configured (e.g. local dev without
 * `.env.local`), we skip the refresh silently — the app still serves
 * unauthenticated pages and the helpers in `src/server/auth/` fail closed.
 */
export async function middleware(request: NextRequest): Promise<NextResponse> {
  const response = intlMiddleware(request);

  if (!env.NEXT_PUBLIC_SUPABASE_URL || !env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    return response;
  }

  const supabase = createServerClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (cookiesToSet: { name: string; value: string; options: CookieOptions }[]) => {
          cookiesToSet.forEach(({ name, value, options }) => {
            // Mirror writes onto both the in-flight request (so subsequent
            // middleware reads see the new value) and the outbound response
            // (so the browser receives the cookie).
            request.cookies.set(name, value);
            response.cookies.set(name, value, options);
          });
        },
      },
    },
  );

  // Triggering getUser() causes @supabase/ssr to refresh the session cookie
  // if it has expired or is close to expiry. The user object itself is
  // discarded here — downstream code reads it via the server helpers.
  await supabase.auth.getUser();

  return response;
}

export const config = {
  // Match everything except Next internals, static assets, and the API.
  matcher: ['/((?!api|_next|_vercel|.*\\..*).*)'],
};
