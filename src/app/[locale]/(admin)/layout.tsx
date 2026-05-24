import { redirect } from 'next/navigation';

import { type Route } from 'next';
import { getLocale } from 'next-intl/server';

import { getCurrentProfile } from '@/server/auth/get-current-profile';

/**
 * The admin / moderation route group.
 *
 * Access is gated server-side at the layout level. The check happens here,
 * not in middleware, because the role lookup needs the database
 * (`profiles.role`) and middleware should not run a query on every
 * request. Routes inside `(admin)/` are therefore safe to render —
 * unauthenticated or under-privileged users are redirected before any
 * admin component executes.
 *
 * Redirect strategy:
 *   - no session         → /login
 *   - role = 'user'      → /          (no admin access)
 *   - role = 'moderator' → render
 *   - role = 'admin'     → render
 *
 * No content from the admin surface is rendered to disallowed users, and
 * no detail about why access was denied is exposed (per
 * `docs/SECURITY_RULES.md` §4).
 */
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const profile = await getCurrentProfile();
  const locale = await getLocale();
  const prefix = locale === 'da' ? '' : `/${locale}`;

  if (!profile) {
    redirect(`${prefix}/login` as Route);
  }

  if (profile.role !== 'moderator' && profile.role !== 'admin') {
    redirect(`${prefix}/` as Route);
  }

  return (
    <section className="container py-8">
      <div className="rounded-md border border-dashed bg-muted/40 p-6">{children}</div>
    </section>
  );
}
