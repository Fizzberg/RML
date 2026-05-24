import 'server-only';

import { createSupabaseServerClient } from '@/server/db/supabase-server';

export type AppRole = 'user' | 'moderator' | 'admin';

/**
 * The minimal slice of `profiles` that any server-side helper / layout needs
 * to gate access. Never includes private columns beyond the role enum.
 */
export interface CurrentProfile {
  id: string;
  display_name: string;
  locale: 'da' | 'en';
  role: AppRole;
  deleted_at: string | null;
}

/**
 * Returns the calling user's profile or null.
 *
 * Fail-closed behaviour (returns null) when:
 *   - no Supabase session;
 *   - Supabase env is not configured (build-time / misconfigured dev);
 *   - the `profiles` row is missing (should not happen because of the
 *     `handle_new_auth_user` trigger, but we never trust that to hold);
 *   - the profile is tombstoned (`deleted_at IS NOT NULL`).
 *
 * The query reads the base `profiles` table under the user's own session.
 * RLS policy `profiles_select_self` permits reading exactly the caller's
 * own row; no other rows are visible through this code path.
 */
export async function getCurrentProfile(): Promise<CurrentProfile | null> {
  let supabase;
  try {
    supabase = await createSupabaseServerClient();
  } catch {
    // Supabase env is not configured — treat as unauthenticated.
    return null;
  }

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return null;
  }

  const { data, error } = await supabase
    .from('profiles')
    .select('id, display_name, locale, role, deleted_at')
    .eq('id', user.id)
    .maybeSingle<CurrentProfile>();

  if (error || !data) {
    return null;
  }

  if (data.deleted_at !== null) {
    // Tombstoned — treat as unauthenticated for app purposes.
    return null;
  }

  return data;
}
