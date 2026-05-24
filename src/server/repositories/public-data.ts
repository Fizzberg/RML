import 'server-only';

import { createSupabaseServerClient } from '@/server/db/supabase-server';

/**
 * Public-data repository.
 *
 * The ONLY layer that talks to Supabase for these surfaces. Reads exclusively
 * from `public_*` views (never base tables) so that no private/private-mixed
 * column can leak through this code path — see `docs/SECURITY_RULES.md` §9
 * and `docs/SCHEMA_REVIEW.md` §3 / §5.
 *
 * Used for the first end-to-end read test from the Next.js app to the local
 * Supabase stack (the `/[locale]/dev/public-data` page). Will be extended
 * (and split per domain) as real product surfaces are built.
 */

// -----------------------------------------------------------------------------
// Row types — mirror the SELECT lists in supabase/migrations/2026…schema_v1
// for `public_addresses`, `public_companies`, and `public_tenancy_reviews`.
// -----------------------------------------------------------------------------

export interface PublicAddressRow {
  id: string;
  street: string;
  house_number: string;
  postal_code: string;
  city: string;
  building_id: string | null;
}

export type CompanyStatus = 'active' | 'dissolved' | 'unknown';

export interface PublicCompanyRow {
  id: string;
  cvr_number: string;
  name: string;
  company_type: string | null;
  status: CompanyStatus;
}

export type DepositReturnState =
  | 'full'
  | 'partial'
  | 'none'
  | 'not_applicable'
  | 'pending';

export type MouldSeverity = 'none' | 'minor' | 'significant';

export type VerificationState =
  | 'unverified'
  | 'pending_verification'
  | 'verified'
  | 'verification_failed';

export interface PublicReviewRow {
  id: string;
  address_id: string;
  company_id: string | null;
  dwelling_id: string | null;
  author_display_name: string;
  overall_rating: number;
  communication_rating: number | null;
  contract_fairness_rating: number | null;
  maintenance_rating: number | null;
  location_rating: number | null;
  monthly_rent: number | null;
  deposit_amount: number | null;
  deposit_returned: DepositReturnState | null;
  mould: MouldSeverity | null;
  issue_categories: string[];
  tenancy_start: string;
  tenancy_end: string | null;
  general_text: string | null;
  verification_status: VerificationState;
  published_at: string;
  last_edited_at: string | null;
  is_edited: boolean;
}

// -----------------------------------------------------------------------------
// Queries
// -----------------------------------------------------------------------------

const DEFAULT_LIMIT = 20;

export async function listPublicAddresses(
  limit: number = DEFAULT_LIMIT,
): Promise<PublicAddressRow[]> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from('public_addresses')
    .select('id, street, house_number, postal_code, city, building_id')
    .order('postal_code', { ascending: true })
    .limit(limit)
    .returns<PublicAddressRow[]>();

  if (error) {
    throw new Error(`public_addresses query failed: ${error.message}`);
  }
  return data ?? [];
}

export async function listPublicCompanies(
  limit: number = DEFAULT_LIMIT,
): Promise<PublicCompanyRow[]> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from('public_companies')
    .select('id, cvr_number, name, company_type, status')
    .order('cvr_number', { ascending: true })
    .limit(limit)
    .returns<PublicCompanyRow[]>();

  if (error) {
    throw new Error(`public_companies query failed: ${error.message}`);
  }
  return data ?? [];
}

export async function listPublicReviews(
  limit: number = DEFAULT_LIMIT,
): Promise<PublicReviewRow[]> {
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from('public_tenancy_reviews')
    .select(
      [
        'id',
        'address_id',
        'company_id',
        'dwelling_id',
        'author_display_name',
        'overall_rating',
        'communication_rating',
        'contract_fairness_rating',
        'maintenance_rating',
        'location_rating',
        'monthly_rent',
        'deposit_amount',
        'deposit_returned',
        'mould',
        'issue_categories',
        'tenancy_start',
        'tenancy_end',
        'general_text',
        'verification_status',
        'published_at',
        'last_edited_at',
        'is_edited',
      ].join(', '),
    )
    .order('published_at', { ascending: false })
    .limit(limit)
    .returns<PublicReviewRow[]>();

  if (error) {
    throw new Error(`public_tenancy_reviews query failed: ${error.message}`);
  }
  return data ?? [];
}
