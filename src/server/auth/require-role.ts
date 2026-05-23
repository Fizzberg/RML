import 'server-only';

import { getCurrentUser } from './get-session';

/**
 * The role enum source of truth lives in `profiles.role` (see
 * `docs/SECURITY_RULES.md` §12). Application code reads it through here; it
 * is never derived from a client-supplied claim.
 */
export type AppRole = 'user' | 'moderator' | 'admin';

/**
 * Resolve the calling user's role by reading `profiles.role`.
 *
 * Fails closed: if there is no session, or no `profiles` row, returns `null`.
 * Callers that require a role must treat `null` as denial.
 *
 * Scaffold only — the actual `profiles` repository will be implemented when
 * the auth feature is built. Today this returns `null` so privileged code
 * cannot accidentally pass a role check.
 */
export async function getCurrentRole(): Promise<AppRole | null> {
  const user = await getCurrentUser();
  if (!user) return null;

  // TODO(auth): read role from `profiles` via the profiles repository once it
  // exists. Until then, fail closed — see docs/SECURITY_RULES.md §13.
  return null;
}

/**
 * Assert that the caller has one of the allowed roles. Throws a generic error
 * otherwise — UI surfaces a generic message; details stay in server logs
 * (see `docs/SECURITY_RULES.md` §4).
 */
export async function requireRole(allowed: readonly AppRole[]): Promise<AppRole> {
  const role = await getCurrentRole();
  if (!role || !allowed.includes(role)) {
    throw new Error('forbidden');
  }
  return role;
}
