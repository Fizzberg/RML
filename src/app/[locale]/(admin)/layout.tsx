/**
 * The admin/moderation route group.
 *
 * Access control will be enforced server-side via `requireRole(['moderator',
 * 'admin'])` once the role mechanism is wired up (see
 * `docs/SECURITY_RULES.md` §12). For now this layout is presentation only;
 * the route is **not** protected yet — do not deploy this surface to a real
 * environment until the role check is in place.
 */
export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <section className="container py-8">
      <div className="rounded-md border border-dashed bg-muted/40 p-6">{children}</div>
    </section>
  );
}
