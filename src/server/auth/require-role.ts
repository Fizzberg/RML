import 'server-only';

import { getCurrentProfile, type AppRole } from './get-current-profile';

export type { AppRole };

/**
 * Resolve the calling user's role by reading `profiles.role`.
 *
 * Fail-closed: if there is no session, the profile row is missing, the
 * profile is tombstoned, or Supabase is not configured, this returns
 * `null`. Callers that require a role must treat `null` as denial.
 */
export async function getCurrentRole(): Promise<AppRole | null> {
  const profile = await getCurrentProfile();
  return profile?.role ?? null;
}

/**
 * Assert that the caller has one of the allowed roles. Throws a generic
 * 'forbidden' error otherwise — surface that as a generic message to the
 * user (per `docs/SECURITY_RULES.md` §4); details stay in server logs.
 *
 * Layouts and pages that want a redirect-on-forbidden behaviour should use
 * `getCurrentProfile()` directly and call `redirect()` themselves.
 */
export async function requireRole(allowed: readonly AppRole[]): Promise<AppRole> {
  const role = await getCurrentRole();
  if (!role || !allowed.includes(role)) {
    throw new Error('forbidden');
  }
  return role;
}
