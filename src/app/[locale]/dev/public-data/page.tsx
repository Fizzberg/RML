import { getTranslations } from 'next-intl/server';

import {
  listPublicAddresses,
  listPublicCompanies,
  listPublicReviews,
  type PublicAddressRow,
  type PublicCompanyRow,
  type PublicReviewRow,
} from '@/server/repositories/public-data';

/**
 * Local-development-only page that proves the end-to-end read path from a
 * server component, through the `public-data` repository, to the local
 * Supabase `public_*` views.
 *
 * - No base-table access (the repository reads only public views).
 * - No private fields exposed: floor / door / geo / evidence metadata are
 *   excluded by the views themselves.
 * - Only `moderation_status = 'approved'` rows appear, also by virtue of
 *   the views' WHERE clauses.
 * - This route is NOT a product page. It is a debug surface.
 */

// Always render on demand. Uses `cookies()` indirectly (via the Supabase
// server client) and reads from a live DB; not safe to prerender.
export const dynamic = 'force-dynamic';

export default async function PublicDataDevPage() {
  const t = await getTranslations('dev.publicData');

  const [addresses, companies, reviews] = await Promise.all([
    listPublicAddresses(20),
    listPublicCompanies(20),
    listPublicReviews(20),
  ]);

  return (
    <section className="container space-y-8 py-8">
      <header>
        <h1 className="text-xl font-semibold tracking-tight">{t('title')}</h1>
        <p className="mt-1 text-sm text-muted-foreground">{t('notice')}</p>
      </header>

      <DevSection title={`${t('addresses')} (${addresses.length})`}>
        <AddressTable rows={addresses} emptyLabel={t('empty')} />
      </DevSection>

      <DevSection title={`${t('companies')} (${companies.length})`}>
        <CompanyTable rows={companies} emptyLabel={t('empty')} />
      </DevSection>

      <DevSection title={`${t('reviews')} (${reviews.length})`}>
        <ReviewTable rows={reviews} emptyLabel={t('empty')} />
      </DevSection>
    </section>
  );
}

function DevSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section>
      <h2 className="mb-2 border-b pb-1 text-sm font-medium tracking-tight text-foreground">
        {title}
      </h2>
      {children}
    </section>
  );
}

function AddressTable({ rows, emptyLabel }: { rows: PublicAddressRow[]; emptyLabel: string }) {
  return (
    <table className="w-full text-xs font-mono">
      <thead className="text-muted-foreground">
        <tr className="border-b">
          <Th>postal_code</Th>
          <Th>street</Th>
          <Th>house_number</Th>
          <Th>city</Th>
        </tr>
      </thead>
      <tbody>
        {rows.map((a) => (
          <tr key={a.id} className="border-b border-dashed last:border-b-0">
            <Td>{a.postal_code}</Td>
            <Td>{a.street}</Td>
            <Td>{a.house_number}</Td>
            <Td>{a.city}</Td>
          </tr>
        ))}
        {rows.length === 0 && (
          <tr>
            <Td colSpan={4} muted>
              {emptyLabel}
            </Td>
          </tr>
        )}
      </tbody>
    </table>
  );
}

function CompanyTable({ rows, emptyLabel }: { rows: PublicCompanyRow[]; emptyLabel: string }) {
  return (
    <table className="w-full text-xs font-mono">
      <thead className="text-muted-foreground">
        <tr className="border-b">
          <Th>cvr_number</Th>
          <Th>name</Th>
          <Th>status</Th>
        </tr>
      </thead>
      <tbody>
        {rows.map((c) => (
          <tr key={c.id} className="border-b border-dashed last:border-b-0">
            <Td>{c.cvr_number}</Td>
            <Td>{c.name}</Td>
            <Td>{c.status}</Td>
          </tr>
        ))}
        {rows.length === 0 && (
          <tr>
            <Td colSpan={3} muted>
              {emptyLabel}
            </Td>
          </tr>
        )}
      </tbody>
    </table>
  );
}

function ReviewTable({ rows, emptyLabel }: { rows: PublicReviewRow[]; emptyLabel: string }) {
  return (
    <table className="w-full text-xs font-mono">
      <thead className="text-muted-foreground">
        <tr className="border-b">
          <Th>author</Th>
          <Th>rating</Th>
          <Th>deposit_returned</Th>
          <Th>mould</Th>
          <Th>verification</Th>
          <Th>company_linked</Th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => (
          <tr key={r.id} className="border-b border-dashed last:border-b-0">
            <Td>{r.author_display_name}</Td>
            <Td>{r.overall_rating}</Td>
            <Td>{r.deposit_returned ?? '—'}</Td>
            <Td>{r.mould ?? '—'}</Td>
            <Td>{r.verification_status}</Td>
            <Td>{r.company_id ? 'yes' : 'no'}</Td>
          </tr>
        ))}
        {rows.length === 0 && (
          <tr>
            <Td colSpan={6} muted>
              {emptyLabel}
            </Td>
          </tr>
        )}
      </tbody>
    </table>
  );
}

function Th({ children }: { children: React.ReactNode }) {
  return <th className="py-1 pr-4 text-left font-medium">{children}</th>;
}

function Td({
  children,
  colSpan,
  muted = false,
}: {
  children: React.ReactNode;
  colSpan?: number;
  muted?: boolean;
}) {
  return (
    <td
      colSpan={colSpan}
      className={`py-1 pr-4 ${muted ? 'text-muted-foreground' : ''}`}
    >
      {children}
    </td>
  );
}
