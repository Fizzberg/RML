import 'server-only';

import { createSupabaseServerClient } from '@/server/db/supabase-server';

/**
 * Returns the current authenticated user, or `null` if the request has no
 * session. Use this at the boundary of server actions and route handlers
 * before any privileged work.
 *
 * Scaffold only — concrete session shape and error handling will be added
 * with the auth feature. This is the single chokepoint for "who is calling".
 */
export async function getCurrentUser() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    return null;
  }

  return user;
}
