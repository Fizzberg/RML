-- =============================================================================
-- Migration:    20260524000000_schema_v1_proposal.sql
-- Origin:       Initial schema draft for RML (review proposal v1).
-- Date/context: 2026-05-24. Drafted on branch `feature/schema-v1-proposal`.
-- Idempotent:   Yes, where practical (DO-blocks for enums, IF [NOT] EXISTS for
--               tables/indexes/policies/triggers, CREATE OR REPLACE for funcs).
-- Risk level:   PROPOSAL — DO NOT APPLY.
--
-- This file is a *review draft*. It is intentionally NOT applied to any
-- environment. The purpose is to circulate the data model + RLS + view +
-- trigger strategy for human review before a real migration is created.
--
-- Companion document: docs/SCHEMA_REVIEW.md
--
-- Governance references:
--   - docs/DATA_MODEL.md          (entities, public vs private fields, audit)
--   - docs/SECURITY_RULES.md      (RLS, storage, public-read pattern, roles)
--   - docs/MODERATION_POLICY.md   (event log, append-only, edits)
--   - docs/PRODUCT_DECISIONS.md   (decisions 9, 10; open questions)
--   - docs/ARCHITECTURE.md        (server/repositories ↔ public_* views)
--   - CLAUDE.md                   (§5 migration discipline, §6 security)
--
-- Conventions used in this draft:
--   * All identifiers are snake_case, plural for tables, singular for enums.
--   * Audit timestamps are timestamptz NOT NULL DEFAULT now().
--   * Primary keys are uuid v7-ish (gen_random_uuid for now; v7 needs ext).
--   * RLS is enabled in the same statement block as the table.
--   * Public reads go through `public_*` views — anon never gets SELECT on a
--     base table that mixes public and private columns.
--   * `moderation_events` is enforced append-only by absence of UPDATE/DELETE
--     policies AND by a defensive trigger.
--   * The freeze rule (DATA_MODEL §3.1) is enforced by a trigger that blocks
--     direct edits of public-content columns once moderation_status='approved'.
--
-- v1 decisions explicitly applied in this draft (see SCHEMA_REVIEW §1):
--   * Public address view withholds floor / door / unit / geo (anti-doxxing).
--   * Company replies disabled in v1; rep-verification deferred.
--   * Verification badge exposed as a simple state only, never evidence detail.
--   * Verification documents: 90-day default retention (sweeper TBD).
--   * Display names: duplicates allowed; no global uniqueness.
--   * Author-per-address uniqueness: NOT enforced at the DB layer.
--   * reports.reporter_id & resolved_by: ON DELETE SET NULL.
--   * moderation_events: polymorphic; actor_id ON DELETE SET NULL.
--   * apply_review_revision: atomic applied_at ratchet + FOR UPDATE + FOUND check.
--   * Initial admin: manual out-of-band UPDATE (no bootstrap RPC).
--   * Deleted profiles: tombstone in profiles + denormalised display-name
--     snapshot on tenancy_reviews so public reviews survive account deletion.
--
-- v1 hardening (resolves SCHEMA_REVIEW I-1 .. I-6):
--   * Column-level UPDATE grants on profiles, tenancy_reviews,
--     tenancy_review_revisions, review_photos, verification_documents — the
--     "default to denied, opt-in by column" posture closes role-escalation,
--     snapshot-tampering, and status-self-approval paths structurally.
--   * apply_review_revision is idempotent (applied_at ratchet) and raises
--     cleanly when the underlying review was deleted post-approval.
--   * moderation_events is also TRUNCATE-protected via a STATEMENT trigger.
--   * Explicit EXECUTE grants on the RLS helper functions so hardened
--     Supabase setups (no default PUBLIC grants) keep working.
--   * Profile-provisioning trigger sanitises locale metadata so signup
--     cannot be DoS'd by a bad client-side locale string.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. EXTENSIONS
-- -----------------------------------------------------------------------------
-- pgcrypto: gen_random_uuid() for primary keys.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- pg_trgm: trigram index for company name and address ILIKE search.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- NOTE: PostGIS is NOT enabled here. Geo coordinates on addresses are stored
-- as plain numeric for the initial draft; PostGIS would be a separate, deliberate
-- decision tied to the import pipeline (`docs/ARCHITECTURE.md` §7).


-- -----------------------------------------------------------------------------
-- 1. ENUM TYPES
-- -----------------------------------------------------------------------------
-- Wrapped in DO-blocks because `CREATE TYPE` has no `IF NOT EXISTS` form.

DO $$ BEGIN
  CREATE TYPE app_role AS ENUM ('user', 'moderator', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE moderation_status AS ENUM ('pending', 'approved', 'rejected', 'removed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE verification_status AS ENUM (
    'unverified', 'pending_verification', 'verified', 'verification_failed'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE deposit_return_status AS ENUM (
    'full', 'partial', 'none', 'not_applicable', 'pending'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE mould_severity AS ENUM ('none', 'minor', 'significant');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE report_status AS ENUM ('open', 'under_review', 'resolved', 'dismissed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 'false_information' (not 'false', which is a SQL keyword).
DO $$ BEGIN
  CREATE TYPE report_reason AS ENUM (
    'false_information', 'doxxing', 'harassment', 'spam', 'off_topic', 'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE revision_status AS ENUM ('pending', 'approved', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE company_status AS ENUM ('active', 'dissolved', 'unknown');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE verification_document_type AS ENUM (
    'lease', 'utility_bill', 'deposit_receipt', 'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE evidence_review_status AS ENUM ('pending', 'accepted', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Event types for moderation_events. Append-only; new values are added in
-- their own migration, never removed.
DO $$ BEGIN
  CREATE TYPE moderation_event_type AS ENUM (
    'submitted',
    'approved',
    'rejected',
    'removed',
    'verification_reviewed',
    'reply_approved',
    'reply_rejected',
    'report_resolved',
    'report_dismissed',
    'evidence_accessed',
    'role_changed',
    'review_resubmitted',
    'photo_approved',
    'photo_rejected'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Sub-rating scale is a small int (1..5). We keep it as integer with a CHECK,
-- rather than an enum, so aggregates (AVG) work naturally.


-- -----------------------------------------------------------------------------
-- 2. SHARED HELPER FUNCTIONS
-- -----------------------------------------------------------------------------

-- Updated-at trigger function — invoked by tg_set_updated_at on each mutable
-- table.
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- Convenience: is the calling user a moderator or admin?
-- Used inside RLS policies. SECURITY DEFINER so the policy can read profiles
-- regardless of the caller's RLS on profiles. Marked STABLE so the planner
-- can cache the result within a statement.
CREATE OR REPLACE FUNCTION public.is_moderator_or_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('moderator', 'admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role = 'admin'
  );
$$;

-- Explicit EXECUTE grants. Both helpers inspect only the caller's own
-- auth.uid() (they cannot be coerced into checking another user's role),
-- so granting to anon is safe. Hardened Supabase setups that strip default
-- PUBLIC grants on public-schema functions would otherwise silently break
-- the RLS policies that depend on these.
REVOKE ALL ON FUNCTION public.is_moderator_or_admin() FROM public;
GRANT EXECUTE ON FUNCTION public.is_moderator_or_admin() TO anon, authenticated;

REVOKE ALL ON FUNCTION public.is_admin() FROM public;
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;


-- -----------------------------------------------------------------------------
-- 3. TABLES
-- -----------------------------------------------------------------------------

-- 3.1 profiles ----------------------------------------------------------------
-- One row per auth.users row. Provisioned automatically by trigger (§7).
--
-- `role` is the SOURCE OF TRUTH for authorisation (SECURITY_RULES §12). It is
-- not self-writable; the only mutator is the admin RPC `admin_set_user_role`
-- (§6.1), and every role change writes a `role_changed` event.
--
-- `display_name` is a *pseudonymous* public handle. v1 deliberately does **not**
-- enforce uniqueness:
--   - Pseudonymity is the design goal (DESIGN_PRINCIPLES §1, PRODUCT_DECISIONS §2).
--   - Global uniqueness creates pressure toward real-name handles and
--     name-squatting incentives.
--   - The reviewer's identity is communicated by display_name + the page they
--     reviewed; collisions are visually acceptable and not security-relevant.
--   - The opaque `user-XXXXXXXX` default produced by the provisioning trigger
--     (§7) gives a high-probability-unique handle out of the box without a
--     constraint.
--
-- `deleted_at` marks a tombstoned profile. v1 uses a soft-delete (tombstone)
-- strategy for account deletion (PRODUCT_DECISIONS §11 / SCHEMA_REVIEW §6):
--   - On account deletion the row is anonymised (display_name replaced with a
--     neutral tombstone marker, deleted_at set), NOT hard-deleted.
--   - Approved tenancy_reviews carry a denormalised display-name snapshot
--     (`tenancy_reviews.author_display_name_snapshot`) so the public view
--     does not depend on the profiles row continuing to exist with the
--     original handle.
--   - If `auth.users` is ever hard-deleted, the cascade removes profiles,
--     but the snapshot on the review preserves the public view. FK chains
--     downstream of profiles use ON DELETE SET NULL to keep author-attached
--     artefacts (reviews, photos, evidence, events) intact with author_id = NULL.
CREATE TABLE IF NOT EXISTS public.profiles (
  id           uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  locale       text NOT NULL DEFAULT 'da' CHECK (locale IN ('da', 'en')),
  role         app_role NOT NULL DEFAULT 'user',
  deleted_at   timestamptz,                          -- tombstone marker (v1 soft-delete)
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- NOTE: no uniqueness index on display_name. v1 allows duplicates by design.
-- Lookups by display_name are not a primary access pattern; if needed later,
-- add a non-unique index or trigram.

-- Partial index over tombstoned profiles for cleanup and "is this user
-- soft-deleted?" lookups. Active profiles are not in the index.
CREATE INDEX IF NOT EXISTS profiles_deleted_at_idx
  ON public.profiles (deleted_at)
  WHERE deleted_at IS NOT NULL;

DROP TRIGGER IF EXISTS profiles_set_updated_at ON public.profiles;
CREATE TRIGGER profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Column-level UPDATE grants (critical — prevents role self-escalation).
--   * `role` and `deleted_at` are NEVER user-mutable. They are set only via
--     the SECURITY DEFINER paths (`admin_set_user_role`, the deletion RPC,
--     or service-role code).
--   * `display_name` and `locale` are user-mutable from /account.
-- The RLS policy `profiles_update_self_limited` gates which ROWS a user can
-- touch; these column grants gate which COLUMNS. Both layers must allow.
REVOKE UPDATE ON public.profiles FROM anon, authenticated;
GRANT UPDATE (display_name, locale) ON public.profiles TO authenticated;


-- 3.2 buildings ---------------------------------------------------------------
-- BBR reference data. Populated by the import pipeline later.
CREATE TABLE IF NOT EXISTS public.buildings (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bbr_building_id  text UNIQUE,                 -- nullable until imported
  build_year       int  CHECK (build_year BETWEEN 1500 AND 2100),
  building_type    text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS buildings_set_updated_at ON public.buildings;
CREATE TRIGGER buildings_set_updated_at
  BEFORE UPDATE ON public.buildings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.buildings ENABLE ROW LEVEL SECURITY;


-- 3.3 addresses ---------------------------------------------------------------
-- DAR/Datafordeleren reference data. Populated by the import pipeline later.
--
-- Anti-doxxing: `floor`, `door`, and `geo_lat`/`geo_lon` are stored internally
-- so the platform can disambiguate units for moderation, verification, tenancy
-- linkage, and abuse workflows. They are **NEVER** exposed by any public view
-- in v1 (`public_addresses` excludes them by design — see §5.1). This is a
-- binding v1 decision: public pages must not isolate a single household.
-- Exposing them publicly would require a separate, documented decision and
-- would not be reversed casually.
--
-- Even moderators see floor/door only when handling a specific submission;
-- the moderation UI should not list floor/door in any aggregate listing.
CREATE TABLE IF NOT EXISTS public.addresses (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dar_address_id   text UNIQUE,                  -- nullable until imported
  street           text NOT NULL,
  house_number     text NOT NULL,
  floor            text,                         -- doxxing-sensitive
  door             text,                         -- doxxing-sensitive
  postal_code      text NOT NULL CHECK (postal_code ~ '^[0-9]{4}$'),
  city             text NOT NULL,
  building_id      uuid REFERENCES public.buildings(id),
  geo_lat          numeric(9, 6),                -- doxxing-sensitive
  geo_lon          numeric(9, 6),                -- doxxing-sensitive
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS addresses_postal_city_street_idx
  ON public.addresses (postal_code, city, street);

CREATE INDEX IF NOT EXISTS addresses_building_id_idx
  ON public.addresses (building_id);

-- Trigram index for street autocomplete. Combined with the rate-limited
-- search endpoint and minimum prefix length (SECURITY_RULES §6).
CREATE INDEX IF NOT EXISTS addresses_street_trgm_idx
  ON public.addresses USING gin (street gin_trgm_ops);

DROP TRIGGER IF EXISTS addresses_set_updated_at ON public.addresses;
CREATE TRIGGER addresses_set_updated_at
  BEFORE UPDATE ON public.addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;


-- 3.4 dwellings ---------------------------------------------------------------
-- BBR unit-level reference data, attached to an address.
CREATE TABLE IF NOT EXISTS public.dwellings (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  address_id      uuid NOT NULL REFERENCES public.addresses(id) ON DELETE RESTRICT,
  bbr_dwelling_id text UNIQUE,                  -- nullable until imported
  area_m2         numeric(6, 2) CHECK (area_m2 >= 0),
  rooms           numeric(3, 1) CHECK (rooms >= 0),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS dwellings_address_id_idx ON public.dwellings (address_id);

DROP TRIGGER IF EXISTS dwellings_set_updated_at ON public.dwellings;
CREATE TRIGGER dwellings_set_updated_at
  BEFORE UPDATE ON public.dwellings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.dwellings ENABLE ROW LEVEL SECURITY;


-- 3.5 companies ---------------------------------------------------------------
-- CVR-identified companies only. Private individual landlords do not have a
-- companies row and do not have a standalone profile page
-- (PRODUCT_DECISIONS §10).
CREATE TABLE IF NOT EXISTS public.companies (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cvr_number    text NOT NULL UNIQUE CHECK (cvr_number ~ '^[0-9]{8}$'),
  name          text NOT NULL,
  company_type  text,
  status        company_status NOT NULL DEFAULT 'unknown',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS companies_name_trgm_idx
  ON public.companies USING gin (name gin_trgm_ops);

DROP TRIGGER IF EXISTS companies_set_updated_at ON public.companies;
CREATE TRIGGER companies_set_updated_at
  BEFORE UPDATE ON public.companies
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;


-- 3.6 tenancy_reviews ---------------------------------------------------------
-- A single tenancy experience. Public-safe and private-but-author-only columns
-- coexist on this table; anon NEVER receives SELECT on it directly. Public
-- reads go through public_tenancy_reviews (§5).
--
-- author_id is ON DELETE SET NULL so that a profile tombstone (or a hard
-- cascade from auth.users) does NOT destroy the public review. The display
-- name visible on the public page comes from `author_display_name_snapshot`
-- (denormalised at insert and on revision-apply), so the review stays
-- attributable to a pseudonymous handle even when the profiles row is gone.
-- This implements the v1 decision: published reviews remain visible after
-- account deletion where legally permissible (SCHEMA_REVIEW §1.11 and §7).
CREATE TABLE IF NOT EXISTS public.tenancy_reviews (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Linkage
  author_id       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  address_id      uuid NOT NULL REFERENCES public.addresses(id) ON DELETE RESTRICT,
  dwelling_id     uuid REFERENCES public.dwellings(id),
  -- NULL when the landlord is a private individual (no CVR). PRODUCT_DECISIONS §10.
  company_id      uuid REFERENCES public.companies(id),

  -- Denormalised pseudonymous display name at submission / revision-apply time.
  -- Public views read this directly (no JOIN to profiles) so account-deletion
  -- cannot make an approved review disappear. NOT NULL — populated by the
  -- BEFORE INSERT trigger `tg_snapshot_review_display_name` (§7.5) and
  -- refreshed inside `apply_review_revision` (§6.2).
  author_display_name_snapshot text NOT NULL,

  -- Public structured ratings (1..5)
  overall_rating              smallint NOT NULL CHECK (overall_rating  BETWEEN 1 AND 5),
  communication_rating        smallint CHECK (communication_rating    BETWEEN 1 AND 5),
  contract_fairness_rating    smallint CHECK (contract_fairness_rating BETWEEN 1 AND 5),
  maintenance_rating          smallint CHECK (maintenance_rating       BETWEEN 1 AND 5),
  location_rating             smallint CHECK (location_rating          BETWEEN 1 AND 5),

  -- Public structured factual fields
  monthly_rent       numeric(10, 2) CHECK (monthly_rent      >= 0),
  deposit_amount     numeric(10, 2) CHECK (deposit_amount    >= 0),
  deposit_returned   deposit_return_status,
  mould              mould_severity,
  issue_categories   text[] NOT NULL DEFAULT '{}',  -- structured tag set
  tenancy_start      date NOT NULL,
  tenancy_end        date,                          -- NULL = ongoing
  general_text       text,                          -- optional free text

  -- Status fields
  moderation_status   moderation_status   NOT NULL DEFAULT 'pending',
  verification_status verification_status NOT NULL DEFAULT 'unverified',
  is_high_risk        boolean             NOT NULL DEFAULT false,

  -- Audit
  submitted_at   timestamptz,                        -- set on first submission
  published_at   timestamptz,                        -- set when first approved
  last_edited_at timestamptz,                        -- set when a new revision is applied
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),

  -- v1: DB-level author-per-address uniqueness is intentionally NOT enforced.
  -- Premature hard constraints produce false positives for legitimate cases:
  -- couples sharing a tenancy, sequential roommates at the same address,
  -- sublets, and repeat tenancies (same person rents the same address years
  -- apart). Service-layer logic (in `server/services/reviews/`) may enforce
  -- soft rules ("one active *pending* review per author per address"), but
  -- the database accepts the broader space. Revisit if abuse patterns emerge.

  -- Sanity: tenancy_end >= tenancy_start when present.
  CHECK (tenancy_end IS NULL OR tenancy_end >= tenancy_start)
);

CREATE INDEX IF NOT EXISTS tenancy_reviews_author_idx
  ON public.tenancy_reviews (author_id);

CREATE INDEX IF NOT EXISTS tenancy_reviews_address_status_idx
  ON public.tenancy_reviews (address_id, moderation_status);

CREATE INDEX IF NOT EXISTS tenancy_reviews_company_status_idx
  ON public.tenancy_reviews (company_id, moderation_status)
  WHERE company_id IS NOT NULL;

-- Moderation queue: pending first, oldest first.
CREATE INDEX IF NOT EXISTS tenancy_reviews_queue_idx
  ON public.tenancy_reviews (moderation_status, submitted_at)
  WHERE moderation_status = 'pending';

-- Public recency: approved reviews ordered by publication time, newest first.
-- Adds `published_at IS NOT NULL` to the predicate so the index never holds
-- NULL keys (defensive — an `approved` row should always have published_at,
-- but the trigger order during approval is service-controlled).
CREATE INDEX IF NOT EXISTS tenancy_reviews_published_recency_idx
  ON public.tenancy_reviews (published_at DESC)
  WHERE moderation_status = 'approved' AND published_at IS NOT NULL;

-- High-risk queue prioritisation.
CREATE INDEX IF NOT EXISTS tenancy_reviews_high_risk_idx
  ON public.tenancy_reviews (submitted_at)
  WHERE is_high_risk = true AND moderation_status = 'pending';

DROP TRIGGER IF EXISTS tenancy_reviews_set_updated_at ON public.tenancy_reviews;
CREATE TRIGGER tenancy_reviews_set_updated_at
  BEFORE UPDATE ON public.tenancy_reviews
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.tenancy_reviews ENABLE ROW LEVEL SECURITY;

-- Column-level UPDATE grants (critical — protects the display-name snapshot,
-- the status fields, and the audit/identity columns from author tampering).
--   * Authenticated users can UPDATE only the enumerated content columns. The
--     freeze trigger then gates which of those are mutable when the row is
--     `approved` (i.e., the public-content set freezes; this grant defines
--     the *maximum* user-touchable surface across all statuses).
--   * `author_display_name_snapshot` is NOT grantable — only the snapshot
--     trigger (on INSERT) and `apply_review_revision` (via direct UPDATE)
--     write it. This prevents post-publication identity rewrites.
--   * `author_id`, `address_id` and the status / audit columns are also
--     locked out — only service-role / SECURITY DEFINER paths can change them.
REVOKE UPDATE ON public.tenancy_reviews FROM anon, authenticated;
GRANT UPDATE (
  overall_rating, communication_rating, contract_fairness_rating,
  maintenance_rating, location_rating,
  monthly_rent, deposit_amount, deposit_returned, mould,
  issue_categories, tenancy_start, tenancy_end, general_text,
  dwelling_id, company_id
) ON public.tenancy_reviews TO authenticated;


-- 3.7 tenancy_review_revisions ------------------------------------------------
-- Pending edits to an already-approved review. The "review freezing" pattern
-- (DATA_MODEL §3.1, MODERATION_POLICY §1.1): once a review is approved, the
-- author cannot silently mutate the public content. They submit a revision
-- here; once approved, the moderation service applies it to the base row.
--
-- Stored full snapshot of public-content fields per revision so the history
-- is auditable. Photos are not duplicated here — photo lifecycle is its own
-- pending/approved cycle (§3.8).
CREATE TABLE IF NOT EXISTS public.tenancy_review_revisions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id   uuid NOT NULL REFERENCES public.tenancy_reviews(id) ON DELETE CASCADE,
  -- ON DELETE SET NULL: a deleted/tombstoned profile leaves historical
  -- revision rows intact for moderation auditability; only the link goes away.
  author_id   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,

  -- Snapshot of public-content fields proposed for the new version.
  overall_rating              smallint NOT NULL CHECK (overall_rating  BETWEEN 1 AND 5),
  communication_rating        smallint CHECK (communication_rating    BETWEEN 1 AND 5),
  contract_fairness_rating    smallint CHECK (contract_fairness_rating BETWEEN 1 AND 5),
  maintenance_rating          smallint CHECK (maintenance_rating       BETWEEN 1 AND 5),
  location_rating             smallint CHECK (location_rating          BETWEEN 1 AND 5),
  monthly_rent       numeric(10, 2) CHECK (monthly_rent      >= 0),
  deposit_amount     numeric(10, 2) CHECK (deposit_amount    >= 0),
  deposit_returned   deposit_return_status,
  mould              mould_severity,
  issue_categories   text[] NOT NULL DEFAULT '{}',
  tenancy_start      date NOT NULL,
  tenancy_end        date,
  general_text       text,

  status        revision_status NOT NULL DEFAULT 'pending',
  is_high_risk  boolean NOT NULL DEFAULT false,

  submitted_at  timestamptz NOT NULL DEFAULT now(),
  decided_at    timestamptz,
  decided_by    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  -- Idempotency ratchet for apply_review_revision (§6.2). NULL means the
  -- revision has not yet been applied to the live row; non-NULL means it
  -- has, and a second apply attempt must fail. Set atomically via
  -- UPDATE … WHERE applied_at IS NULL RETURNING … inside the function.
  applied_at    timestamptz,

  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- One pending revision per review at a time. (Hard rule — a second pending
-- revision must wait for the first to resolve.)
CREATE UNIQUE INDEX IF NOT EXISTS tenancy_review_revisions_one_pending_uidx
  ON public.tenancy_review_revisions (review_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS tenancy_review_revisions_review_id_idx
  ON public.tenancy_review_revisions (review_id);

DROP TRIGGER IF EXISTS tenancy_review_revisions_set_updated_at
  ON public.tenancy_review_revisions;
CREATE TRIGGER tenancy_review_revisions_set_updated_at
  BEFORE UPDATE ON public.tenancy_review_revisions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.tenancy_review_revisions ENABLE ROW LEVEL SECURITY;

-- Column-level UPDATE grants. Authors may edit the public-content fields of
-- their own pending revision. They may NOT:
--   * change `status` (only moderators can approve/reject),
--   * set `decided_at` / `decided_by` (those record the moderator's action),
--   * set `applied_at` (only `apply_review_revision` ratchets it),
--   * change `is_high_risk` (system-set; moderators may override via RPC),
--   * change `author_id`, `review_id`, or any audit timestamps.
REVOKE UPDATE ON public.tenancy_review_revisions FROM anon, authenticated;
GRANT UPDATE (
  overall_rating, communication_rating, contract_fairness_rating,
  maintenance_rating, location_rating,
  monthly_rent, deposit_amount, deposit_returned, mould,
  issue_categories, tenancy_start, tenancy_end, general_text
) ON public.tenancy_review_revisions TO authenticated;


-- 3.8 review_photos -----------------------------------------------------------
-- Photo attached to a review. The bucket is PRIVATE (`review-photos`). Public
-- pages access photos via short-lived signed URLs minted by the server when
-- both the review and the photo are 'approved'. SECURITY_RULES §3.
CREATE TABLE IF NOT EXISTS public.review_photos (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id         uuid NOT NULL REFERENCES public.tenancy_reviews(id) ON DELETE CASCADE,
  -- ON DELETE SET NULL: a deleted uploader does not remove approved photos
  -- from already-public reviews. Sweepers that want to remove an uploader's
  -- *unapproved* media must do so explicitly before the cascade.
  uploader_id       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  storage_path      text NOT NULL,                  -- `<uid>/reviews/<review_id>/<file>`
  moderation_status moderation_status NOT NULL DEFAULT 'pending',
  caption           text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  UNIQUE (review_id, storage_path)
);

CREATE INDEX IF NOT EXISTS review_photos_review_status_idx
  ON public.review_photos (review_id, moderation_status);

DROP TRIGGER IF EXISTS review_photos_set_updated_at ON public.review_photos;
CREATE TRIGGER review_photos_set_updated_at
  BEFORE UPDATE ON public.review_photos
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.review_photos ENABLE ROW LEVEL SECURITY;

-- Column-level UPDATE grants. The uploader can edit only the optional
-- caption on their own photo. They cannot:
--   * change `moderation_status` (moderator-only),
--   * change `storage_path` or `review_id` (would orphan the storage object),
--   * touch audit columns.
REVOKE UPDATE ON public.review_photos FROM anon, authenticated;
GRANT UPDATE (caption) ON public.review_photos TO authenticated;


-- 3.9 verification_documents --------------------------------------------------
-- Evidence that the reviewer was a real tenant. Most sensitive table in the
-- product. Bucket is PRIVATE (`verification-documents`). NEVER linked from
-- any public path. SECURITY_RULES §8.
--
-- Retention (v1 default): 90 days from upload. The default value below sets
-- `retention_expires_at` to `now() + 90 days` at insert. Exceptions that
-- *pause* or *extend* the retention clock:
--   - active dispute (an open `reports` row referencing this review),
--   - active report under_review,
--   - legal hold (an admin-set flag on the review or evidence row),
--   - moderation escalation.
-- These exceptions are NOT enforced by the schema in v1; they are the
-- responsibility of the retention-sweeper job (NOT YET IMPLEMENTED). The
-- sweeper should refuse to delete an evidence row when any exception is
-- active, and write a `moderation_events` row when it does delete.
-- See SCHEMA_REVIEW §1.4 for the policy default and §9 item 4 for the
-- still-open retention-sweeper item.
CREATE TABLE IF NOT EXISTS public.verification_documents (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id               uuid NOT NULL REFERENCES public.tenancy_reviews(id) ON DELETE CASCADE,
  -- ON DELETE SET NULL: preserves the evidence row for moderation history /
  -- dispute defence even if the uploader account is deleted. The actual
  -- storage object is removed by the retention sweeper, not by FK cascade.
  uploader_id             uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  document_type           verification_document_type NOT NULL,
  storage_path            text NOT NULL,           -- `<uid>/verification/<review_id>/<file>`
  review_status           evidence_review_status NOT NULL DEFAULT 'pending',
  -- v1 default: now() + 90 days. Sweeper deletes the storage object and the
  -- row when this passes AND no retention-pause condition is active.
  retention_expires_at    timestamptz NOT NULL DEFAULT (now() + interval '90 days'),
  -- A boolean shortcut for legal-hold; in v1 this is checked manually by
  -- moderators. The sweeper job (when implemented) reads this flag.
  legal_hold              boolean NOT NULL DEFAULT false,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),

  UNIQUE (review_id, storage_path)
);

CREATE INDEX IF NOT EXISTS verification_documents_review_idx
  ON public.verification_documents (review_id);

CREATE INDEX IF NOT EXISTS verification_documents_uploader_idx
  ON public.verification_documents (uploader_id);

-- For the retention sweeper. Partial: only rows that are not under legal hold
-- are sweepable; the sweeper filters out paused rows in code as well.
CREATE INDEX IF NOT EXISTS verification_documents_retention_idx
  ON public.verification_documents (retention_expires_at)
  WHERE legal_hold = false;

DROP TRIGGER IF EXISTS verification_documents_set_updated_at
  ON public.verification_documents;
CREATE TRIGGER verification_documents_set_updated_at
  BEFORE UPDATE ON public.verification_documents
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.verification_documents ENABLE ROW LEVEL SECURITY;

-- Column-level UPDATE grants. Authenticated users (including the uploader)
-- have NO mutable columns on this table. Once uploaded, only moderators or
-- service-role paths (via RPC) may change `review_status`, `legal_hold`, or
-- `retention_expires_at`. The RLS policy `evidence_update_uploader` permits
-- the row but the absence of any GRANT UPDATE makes the operation fail with
-- a permission error — the policy is effectively dormant by design.
REVOKE UPDATE ON public.verification_documents FROM anon, authenticated;


-- 3.10 moderation_events ------------------------------------------------------
-- Append-only audit log. Enforced both by absence of UPDATE/DELETE policies
-- AND by a defensive trigger (§9). Even moderators/admins cannot mutate rows.
--
-- POLYMORPHIC DESIGN (target_kind + target_id):
-- v1 chooses a single polymorphic event table over a per-entity event-table
-- explosion (`review_events`, `reply_events`, `report_events`, ...). The
-- tradeoff is deliberate:
--   PROs:
--     - One queryable audit log; one append-only invariant to enforce; one
--       set of triggers, indexes, and policies.
--     - Adding a new target_kind in the future is additive — extend the CHECK,
--       add an event_type enum value if needed, no new tables.
--   CONs:
--     - PostgreSQL cannot enforce a FK on `target_id` because the target table
--       depends on `target_kind`. A bug in services can write an event with a
--       non-existent target_id.
--     - Cross-table JOINs require `target_kind` discrimination in client code.
-- Mitigations (v1):
--   - All inserts go through `server/services/moderation/*` helpers that take
--     a typed (kind, id) pair and look up the target row before logging.
--   - A non-binding `validate_moderation_target(kind, id)` SQL function may
--     be added in a follow-up migration as a structural check (still-open
--     question — SCHEMA_REVIEW §9 item 1).
--   - The `target_kind` CHECK enumerates legal kinds — typos cannot pass.
--
-- actor_id is `ON DELETE SET NULL` so that an account deletion anonymises the
-- actor reference (preserving the audit row), instead of cascading and
-- destroying the log.
CREATE TABLE IF NOT EXISTS public.moderation_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_kind     text NOT NULL CHECK (target_kind IN (
    'review', 'reply', 'photo', 'report', 'document', 'profile'
  )),
  target_id       uuid NOT NULL,
  actor_id        uuid REFERENCES public.profiles(id) ON DELETE SET NULL,  -- NULL = system event OR deleted actor
  event_type      moderation_event_type NOT NULL,
  reason          text,
  previous_status text,
  new_status      text,
  metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS moderation_events_target_idx
  ON public.moderation_events (target_kind, target_id, created_at);

CREATE INDEX IF NOT EXISTS moderation_events_actor_idx
  ON public.moderation_events (actor_id, created_at);

ALTER TABLE public.moderation_events ENABLE ROW LEVEL SECURITY;


-- 3.11 company_replies --------------------------------------------------------
-- Right-of-reply mechanism for CVR-identified companies only
-- (PRODUCT_DECISIONS §9). `company_id` is NOT NULL.
--
-- *** v1 STATUS: DEFERRED ***
-- The reply mechanism is shipped in schema only. Writes are blocked at the
-- RLS layer (`replies_insert_disabled` — WITH CHECK (false), §4.10) and no
-- representative-verification mechanism exists in v1. The table is created
-- so that:
--   (a) downstream FKs (`reports.reply_id`) have a target to reference;
--   (b) the `public_company_replies` view can be defined upfront (it returns
--       zero rows in v1 since no reply ever reaches `approved`);
--   (c) when the rep mechanism is approved, enabling replies is a policy
--       change + a new RLS policy, not a schema migration.
-- The author_display_name_snapshot column mirrors the pattern from
-- tenancy_reviews (see §3.6). It is nullable in v1 because no rows can be
-- inserted; when replies are enabled, a snapshot-on-insert trigger analogous
-- to tg_snapshot_review_display_name will populate it and the column will be
-- tightened to NOT NULL in a follow-up migration.
--
-- IMPORTANT: this section must come BEFORE §3.12 reports, because
-- `reports.reply_id` has an inline FK to `public.company_replies(id)`.
CREATE TABLE IF NOT EXISTS public.company_replies (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id         uuid NOT NULL REFERENCES public.tenancy_reviews(id) ON DELETE CASCADE,
  company_id        uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  -- author_id: SET NULL on profile deletion (parallel to tenancy_reviews).
  author_id         uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  -- Denormalised display-name snapshot for the verified representative.
  -- Populated by a snapshot trigger when the reply mechanism is enabled.
  author_display_name_snapshot text,
  body              text NOT NULL CHECK (length(body) BETWEEN 1 AND 4000),
  moderation_status moderation_status NOT NULL DEFAULT 'pending',
  published_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  -- One reply per company per review.
  UNIQUE (review_id, company_id)
);

CREATE INDEX IF NOT EXISTS company_replies_review_status_idx
  ON public.company_replies (review_id, moderation_status);

DROP TRIGGER IF EXISTS company_replies_set_updated_at ON public.company_replies;
CREATE TRIGGER company_replies_set_updated_at
  BEFORE UPDATE ON public.company_replies
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.company_replies ENABLE ROW LEVEL SECURITY;


-- 3.12 reports ----------------------------------------------------------------
-- A user-submitted report against a review or a reply. Reporter identity is
-- private — never shown to the reviewed party or to the public
-- (MODERATION_POLICY §7).
--
-- v1: `reporter_id` is `ON DELETE SET NULL`. Rationale:
--   - The report's *content* (reason, details, target, decision) is part of
--     the moderation record and is operationally useful even after the
--     reporter deletes their account.
--   - The reporter's identity is private to begin with; SET NULL completes
--     the GDPR-erasure step for that link without destroying the moderation
--     history. The associated `moderation_events` rows already anonymise the
--     actor via SET NULL.
--   - A cryptographic identifier (HMAC of user_id) as an alternative was
--     considered (SCHEMA_REVIEW §1.7) but adds key-management work for no
--     concrete v1 benefit; deferred.
-- `resolved_by` is `ON DELETE SET NULL` for the same reason — preserve the
-- record of a resolution decision even if the moderator's account is removed.
CREATE TABLE IF NOT EXISTS public.reports (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id  uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  -- A report targets either a review or a reply (polymorphic XOR via CHECK).
  review_id    uuid REFERENCES public.tenancy_reviews(id) ON DELETE CASCADE,
  reply_id     uuid REFERENCES public.company_replies(id) ON DELETE CASCADE,
  reason       report_reason NOT NULL,
  details      text,
  status       report_status NOT NULL DEFAULT 'open',
  resolved_at  timestamptz,
  resolved_by  uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),

  CHECK (
    (review_id IS NOT NULL AND reply_id IS NULL) OR
    (review_id IS NULL     AND reply_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS reports_review_status_idx
  ON public.reports (review_id, status)
  WHERE review_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS reports_reply_status_idx
  ON public.reports (reply_id, status)
  WHERE reply_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS reports_queue_idx
  ON public.reports (status, created_at)
  WHERE status IN ('open', 'under_review');

DROP TRIGGER IF EXISTS reports_set_updated_at ON public.reports;
CREATE TRIGGER reports_set_updated_at
  BEFORE UPDATE ON public.reports
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;


-- -----------------------------------------------------------------------------
-- 4. RLS POLICIES
-- -----------------------------------------------------------------------------
-- General pattern:
--   * `anon` never SELECTs base tables that mix public/private columns.
--   * Authors (auth.uid() = author_id) see and edit their own rows where
--     appropriate.
--   * Moderators/admins see everything for moderation queues
--     (via is_moderator_or_admin()).
--   * Admins are the only writers of `profiles.role` (via an RPC, not a
--     direct policy — see §6.1).
--   * `moderation_events` has NO update/delete policy and a defensive trigger.

-- 4.1 profiles ----------------------------------------------------------------
DROP POLICY IF EXISTS profiles_select_self          ON public.profiles;
DROP POLICY IF EXISTS profiles_select_moderator     ON public.profiles;
DROP POLICY IF EXISTS profiles_update_self_limited  ON public.profiles;

-- Authenticated users see their own row. Anon does not see any profile.
CREATE POLICY profiles_select_self ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid());

-- Moderators/admins can read all profiles (for moderation context).
CREATE POLICY profiles_select_moderator ON public.profiles
  FOR SELECT TO authenticated
  USING (public.is_moderator_or_admin());

-- Self-update is allowed for display_name and locale ONLY. The `role` column
-- is filtered out at the application layer (services) and also defended by
-- the policy: this UPDATE policy does not protect against changing `role` on
-- its own. Combine with a column-level GRANT or an audited admin RPC for the
-- privileged path. See §6.1 for the role-change RPC sketch.
CREATE POLICY profiles_update_self_limited ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- INSERT is performed only by the auth-user trigger (SECURITY DEFINER, §7).
-- No INSERT policy is granted to authenticated users; the trigger bypasses
-- RLS because it runs as the function owner.

-- DELETE: a user may delete their own profile (account deletion). Cascade
-- removes their reviews-by-FK chain — published reviews are anonymised
-- separately by the deletion service (SECURITY_RULES §7).
DROP POLICY IF EXISTS profiles_delete_self ON public.profiles;
CREATE POLICY profiles_delete_self ON public.profiles
  FOR DELETE TO authenticated
  USING (id = auth.uid());


-- 4.2 buildings / addresses / dwellings ---------------------------------------
-- Reference data. Anon does not need direct SELECT (the public_addresses view
-- handles search results). Authenticated users may SELECT for review
-- submission flows. Writes are restricted to admin/service-role for now.
DROP POLICY IF EXISTS buildings_select_authenticated ON public.buildings;
CREATE POLICY buildings_select_authenticated ON public.buildings
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS addresses_select_authenticated ON public.addresses;
CREATE POLICY addresses_select_authenticated ON public.addresses
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS dwellings_select_authenticated ON public.dwellings;
CREATE POLICY dwellings_select_authenticated ON public.dwellings
  FOR SELECT TO authenticated USING (true);

-- No INSERT/UPDATE/DELETE policies for reference tables — writes only via the
-- import pipeline running with service-role, or via an admin RPC. Anon gets
-- search through public_addresses + public_companies views (§5).


-- 4.3 companies ---------------------------------------------------------------
DROP POLICY IF EXISTS companies_select_authenticated ON public.companies;
CREATE POLICY companies_select_authenticated ON public.companies
  FOR SELECT TO authenticated USING (true);


-- 4.4 tenancy_reviews ---------------------------------------------------------
-- IMPORTANT: anon has NO direct SELECT on this table. Public reads go through
-- public_tenancy_reviews (§5).
DROP POLICY IF EXISTS reviews_select_author      ON public.tenancy_reviews;
DROP POLICY IF EXISTS reviews_select_moderator   ON public.tenancy_reviews;
DROP POLICY IF EXISTS reviews_insert_author      ON public.tenancy_reviews;
DROP POLICY IF EXISTS reviews_update_author      ON public.tenancy_reviews;
DROP POLICY IF EXISTS reviews_delete_author      ON public.tenancy_reviews;

CREATE POLICY reviews_select_author ON public.tenancy_reviews
  FOR SELECT TO authenticated
  USING (author_id = auth.uid());

CREATE POLICY reviews_select_moderator ON public.tenancy_reviews
  FOR SELECT TO authenticated
  USING (public.is_moderator_or_admin());

CREATE POLICY reviews_insert_author ON public.tenancy_reviews
  FOR INSERT TO authenticated
  WITH CHECK (author_id = auth.uid());

-- Updates by author are allowed while the review is `pending` (initial cycle).
-- Once approved, the freeze trigger blocks updates to public-content columns
-- (§9). Other columns (e.g. author-internal flags, if added later) may still
-- be updatable. Authors revise approved reviews via tenancy_review_revisions.
CREATE POLICY reviews_update_author ON public.tenancy_reviews
  FOR UPDATE TO authenticated
  USING (author_id = auth.uid())
  WITH CHECK (author_id = auth.uid());

-- Authors may delete their own review while still `pending`. Once published,
-- deletion goes through a service path that anonymises rather than deletes
-- (GDPR balance with retention; SECURITY_RULES §7).
CREATE POLICY reviews_delete_author ON public.tenancy_reviews
  FOR DELETE TO authenticated
  USING (author_id = auth.uid() AND moderation_status = 'pending');


-- 4.5 tenancy_review_revisions ------------------------------------------------
DROP POLICY IF EXISTS revisions_select_author    ON public.tenancy_review_revisions;
DROP POLICY IF EXISTS revisions_select_moderator ON public.tenancy_review_revisions;
DROP POLICY IF EXISTS revisions_insert_author    ON public.tenancy_review_revisions;
DROP POLICY IF EXISTS revisions_update_author    ON public.tenancy_review_revisions;

CREATE POLICY revisions_select_author ON public.tenancy_review_revisions
  FOR SELECT TO authenticated
  USING (author_id = auth.uid());

CREATE POLICY revisions_select_moderator ON public.tenancy_review_revisions
  FOR SELECT TO authenticated
  USING (public.is_moderator_or_admin());

CREATE POLICY revisions_insert_author ON public.tenancy_review_revisions
  FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid() AND status = 'pending' AND
    EXISTS (
      SELECT 1 FROM public.tenancy_reviews r
      WHERE r.id = review_id AND r.author_id = auth.uid()
    )
  );

-- Author can withdraw their own pending revision (set status='rejected' is
-- not allowed for the author — that decision belongs to a moderator). For
-- now we let the author edit content while it is still pending.
CREATE POLICY revisions_update_author ON public.tenancy_review_revisions
  FOR UPDATE TO authenticated
  USING (author_id = auth.uid() AND status = 'pending')
  WITH CHECK (author_id = auth.uid() AND status = 'pending');


-- 4.6 review_photos -----------------------------------------------------------
DROP POLICY IF EXISTS photos_select_uploader  ON public.review_photos;
DROP POLICY IF EXISTS photos_select_moderator ON public.review_photos;
DROP POLICY IF EXISTS photos_insert_uploader  ON public.review_photos;
DROP POLICY IF EXISTS photos_update_uploader  ON public.review_photos;
DROP POLICY IF EXISTS photos_delete_uploader  ON public.review_photos;

CREATE POLICY photos_select_uploader ON public.review_photos
  FOR SELECT TO authenticated
  USING (uploader_id = auth.uid());

CREATE POLICY photos_select_moderator ON public.review_photos
  FOR SELECT TO authenticated
  USING (public.is_moderator_or_admin());

CREATE POLICY photos_insert_uploader ON public.review_photos
  FOR INSERT TO authenticated
  WITH CHECK (
    uploader_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.tenancy_reviews r
      WHERE r.id = review_id AND r.author_id = auth.uid()
    )
  );

CREATE POLICY photos_update_uploader ON public.review_photos
  FOR UPDATE TO authenticated
  USING (uploader_id = auth.uid())
  WITH CHECK (uploader_id = auth.uid());

CREATE POLICY photos_delete_uploader ON public.review_photos
  FOR DELETE TO authenticated
  USING (uploader_id = auth.uid() AND moderation_status IN ('pending', 'rejected'));


-- 4.7 verification_documents --------------------------------------------------
DROP POLICY IF EXISTS evidence_select_uploader  ON public.verification_documents;
DROP POLICY IF EXISTS evidence_select_moderator ON public.verification_documents;
DROP POLICY IF EXISTS evidence_insert_uploader  ON public.verification_documents;
DROP POLICY IF EXISTS evidence_update_uploader  ON public.verification_documents;
DROP POLICY IF EXISTS evidence_delete_uploader  ON public.verification_documents;

CREATE POLICY evidence_select_uploader ON public.verification_documents
  FOR SELECT TO authenticated
  USING (uploader_id = auth.uid());

CREATE POLICY evidence_select_moderator ON public.verification_documents
  FOR SELECT TO authenticated
  USING (public.is_moderator_or_admin());

CREATE POLICY evidence_insert_uploader ON public.verification_documents
  FOR INSERT TO authenticated
  WITH CHECK (
    uploader_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.tenancy_reviews r
      WHERE r.id = review_id AND r.author_id = auth.uid()
    )
  );

-- Uploader may update caption-like metadata, not `review_status` (moderators
-- own that). The column-level restriction is enforced at the service layer
-- in the proposal; in a follow-up migration we will issue column-level
-- GRANTs to make it structural.
CREATE POLICY evidence_update_uploader ON public.verification_documents
  FOR UPDATE TO authenticated
  USING (uploader_id = auth.uid())
  WITH CHECK (uploader_id = auth.uid());

-- Uploader may delete their own evidence while still pending review.
CREATE POLICY evidence_delete_uploader ON public.verification_documents
  FOR DELETE TO authenticated
  USING (uploader_id = auth.uid() AND review_status = 'pending');


-- 4.8 moderation_events -------------------------------------------------------
-- APPEND-ONLY. SECURITY_RULES §1.
--   * NO update policy. NO delete policy. (Absence = deny under RLS.)
--   * Insert is allowed for moderators/admins; the trigger also enforces
--     immutability defensively in case a future privileged session attempts
--     UPDATE/DELETE.
--   * Reads are restricted to moderators/admins.
DROP POLICY IF EXISTS modevents_select_moderator ON public.moderation_events;
DROP POLICY IF EXISTS modevents_insert_moderator ON public.moderation_events;

CREATE POLICY modevents_select_moderator ON public.moderation_events
  FOR SELECT TO authenticated
  USING (public.is_moderator_or_admin());

CREATE POLICY modevents_insert_moderator ON public.moderation_events
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_moderator_or_admin() AND actor_id = auth.uid()
  );
-- (Insertions by service-role bypass RLS; those still go through the
-- application services that set actor_id appropriately.)


-- 4.9 reports -----------------------------------------------------------------
DROP POLICY IF EXISTS reports_select_reporter  ON public.reports;
DROP POLICY IF EXISTS reports_select_moderator ON public.reports;
DROP POLICY IF EXISTS reports_insert_reporter  ON public.reports;
DROP POLICY IF EXISTS reports_update_moderator ON public.reports;

CREATE POLICY reports_select_reporter ON public.reports
  FOR SELECT TO authenticated
  USING (reporter_id = auth.uid());

CREATE POLICY reports_select_moderator ON public.reports
  FOR SELECT TO authenticated
  USING (public.is_moderator_or_admin());

CREATE POLICY reports_insert_reporter ON public.reports
  FOR INSERT TO authenticated
  WITH CHECK (reporter_id = auth.uid());

CREATE POLICY reports_update_moderator ON public.reports
  FOR UPDATE TO authenticated
  USING (public.is_moderator_or_admin())
  WITH CHECK (public.is_moderator_or_admin());


-- 4.10 company_replies --------------------------------------------------------
-- *** v1 STATUS: DEFERRED — writes disabled. See SCHEMA_REVIEW §1.2. ***
-- The company-representative mechanism (who may post on behalf of a CVR) is
-- not designed in v1. The schema is in place so dependent FKs and views can
-- be defined, but the INSERT policy `replies_insert_disabled` returns
-- WITH CHECK (false) and therefore blocks all writes by `authenticated`
-- users. Service-role bypasses RLS but nothing writes here in v1. When the
-- mechanism is approved, replace this policy with a real one keyed on a
-- representative table (or a service-role-only path with verification).
DROP POLICY IF EXISTS replies_select_authenticated ON public.company_replies;
DROP POLICY IF EXISTS replies_select_moderator     ON public.company_replies;
DROP POLICY IF EXISTS replies_insert_disabled      ON public.company_replies;

CREATE POLICY replies_select_authenticated ON public.company_replies
  FOR SELECT TO authenticated
  USING (author_id = auth.uid());

CREATE POLICY replies_select_moderator ON public.company_replies
  FOR SELECT TO authenticated
  USING (public.is_moderator_or_admin());

-- Placeholder INSERT policy that always denies. Replaced when the
-- company-representative mechanism is designed and approved.
CREATE POLICY replies_insert_disabled ON public.company_replies
  FOR INSERT TO authenticated
  WITH CHECK (false);


-- -----------------------------------------------------------------------------
-- 5. PUBLIC VIEWS (anon-readable read surface)
-- -----------------------------------------------------------------------------
-- Pattern:
--   * Each view selects ONLY public-safe columns.
--   * Each view filters to publishable state (moderation_status = 'approved').
--   * Views run with the privileges of their owner (default in Postgres;
--     we do not opt into security_invoker=true). The owner is the role that
--     creates the view (`postgres` in Supabase), which has SELECT on the
--     base tables.
--   * `anon` is granted SELECT only on the view, never on the base table.

-- 5.1 public_addresses --------------------------------------------------------
-- *** v1 DECISION (binding): public address pages must NOT expose information
-- *** that can isolate a single household.
--
-- Excluded columns and their rationale:
--   - floor   : single-floor/single-unit buildings → identifies one person.
--   - door    : door identifiers → identifies one apartment + occupant.
--   - geo_lat : exact geo → maps to a unique address pin.
--   - geo_lon : same.
--   - dwelling/unit identifiers: by extension, never on the public address
--     view; per-dwelling aggregation must happen behind authenticated paths.
--
-- Withheld in v1 by design. Re-exposing any of these in public requires a
-- separate, documented decision (PRODUCT_DECISIONS) and a follow-up migration.
CREATE OR REPLACE VIEW public.public_addresses AS
SELECT
  a.id,
  a.street,
  a.house_number,
  a.postal_code,
  a.city,
  a.building_id
FROM public.addresses a;

GRANT SELECT ON public.public_addresses TO anon, authenticated;


-- 5.2 public_companies --------------------------------------------------------
-- All CVR-identified companies are public (the existence of the company is
-- already public via CVR). Private individual landlords have no row here
-- and no public page (PRODUCT_DECISIONS §10).
CREATE OR REPLACE VIEW public.public_companies AS
SELECT
  c.id,
  c.cvr_number,
  c.name,
  c.company_type,
  c.status
FROM public.companies c;

GRANT SELECT ON public.public_companies TO anon, authenticated;


-- 5.3 public_tenancy_reviews --------------------------------------------------
-- Public-safe columns of approved reviews.
--
-- DENORMALISED display name (v1):
-- The pseudonymous handle comes from `tenancy_reviews.author_display_name_snapshot`,
-- not from a JOIN to profiles. This decouples the public view from the
-- profile lifecycle: account deletion (tombstone or hard cascade) cannot
-- remove an approved review from the public surface. See SCHEMA_REVIEW §6.
-- The snapshot is set on INSERT and refreshed inside `apply_review_revision`.
--
-- VERIFICATION badge (v1 decision):
-- This view exposes `verification_status` as a *simple state* only:
--   - unverified | pending_verification | verified | verification_failed.
-- It exposes NOTHING about the underlying evidence — no document metadata,
-- no document_type, no review_status timestamps, no link to
-- verification_documents. The UI may use the state to render a small
-- text-and-icon badge (DESIGN_PRINCIPLES §4.2). The badge is privacy-
-- preserving and intentionally minimal.
CREATE OR REPLACE VIEW public.public_tenancy_reviews AS
SELECT
  r.id,
  r.address_id,
  r.company_id,
  r.dwelling_id,
  -- pseudonymous identity only (snapshot — not a JOIN to profiles)
  r.author_display_name_snapshot            AS author_display_name,
  -- structured ratings + factual fields
  r.overall_rating,
  r.communication_rating,
  r.contract_fairness_rating,
  r.maintenance_rating,
  r.location_rating,
  r.monthly_rent,
  r.deposit_amount,
  r.deposit_returned,
  r.mould,
  r.issue_categories,
  r.tenancy_start,
  r.tenancy_end,
  r.general_text,
  -- public moderation + verification signal (no evidence detail; see above)
  r.verification_status,
  r.published_at,
  r.last_edited_at,
  -- a stable "edited" flag for the public UI (`docs/DESIGN_PRINCIPLES.md` §4.3)
  (r.last_edited_at IS NOT NULL)            AS is_edited
FROM public.tenancy_reviews r
WHERE r.moderation_status = 'approved';

GRANT SELECT ON public.public_tenancy_reviews TO anon, authenticated;


-- 5.4 public_review_photos ----------------------------------------------------
-- Photos that are publishable: both the photo and its parent review must be
-- approved. The view exposes `storage_path` (the key) so a server route can
-- mint a short-lived signed URL; anon NEVER receives a long-lived URL.
CREATE OR REPLACE VIEW public.public_review_photos AS
SELECT
  ph.id,
  ph.review_id,
  ph.storage_path,
  ph.caption,
  ph.created_at
FROM public.review_photos ph
JOIN public.tenancy_reviews r ON r.id = ph.review_id
WHERE ph.moderation_status = 'approved'
  AND r.moderation_status  = 'approved';

GRANT SELECT ON public.public_review_photos TO anon, authenticated;


-- 5.5 public_company_replies --------------------------------------------------
-- *** v1 STATUS: empty by construction. ***
-- The view is defined for forward compatibility but returns ZERO rows in v1
-- because the reply mechanism is deferred (no INSERTs reach `approved`):
--   - The `replies_insert_disabled` RLS policy blocks all inserts
--     (§4.10, WITH CHECK (false)).
--   - No company-representative verification mechanism exists yet.
--   - PRODUCT_DECISIONS §9 documents the deferral.
-- Frontend code that reads this view will get an empty set in v1; that is
-- the intended behaviour. When the reply mechanism is approved, the view
-- becomes populated automatically — no view change required.
--
-- Identity exposure mirrors public_tenancy_reviews: pseudonymous display-name
-- snapshot only, no JOIN to profiles, no real-identity link.
CREATE OR REPLACE VIEW public.public_company_replies AS
SELECT
  cr.id,
  cr.review_id,
  cr.company_id,
  cr.author_display_name_snapshot AS author_display_name,
  cr.body,
  cr.published_at
FROM public.company_replies cr
WHERE cr.moderation_status = 'approved';

GRANT SELECT ON public.public_company_replies TO anon, authenticated;


-- 5.6 public_address_aggregates -----------------------------------------------
-- Cheap aggregate view for address pages and search results. Tied to the
-- recency index on tenancy_reviews. Could be materialised later if cost
-- becomes a concern.
CREATE OR REPLACE VIEW public.public_address_aggregates AS
SELECT
  r.address_id,
  COUNT(*)                                 AS approved_review_count,
  AVG(r.overall_rating)::numeric(3, 2)     AS overall_rating_avg,
  MAX(r.published_at)                      AS most_recent_published_at
FROM public.tenancy_reviews r
WHERE r.moderation_status = 'approved'
GROUP BY r.address_id;

GRANT SELECT ON public.public_address_aggregates TO anon, authenticated;


-- 5.7 public_company_aggregates -----------------------------------------------
CREATE OR REPLACE VIEW public.public_company_aggregates AS
SELECT
  r.company_id,
  COUNT(*)                                 AS approved_review_count,
  AVG(r.overall_rating)::numeric(3, 2)     AS overall_rating_avg,
  MAX(r.published_at)                      AS most_recent_published_at
FROM public.tenancy_reviews r
WHERE r.moderation_status = 'approved'
  AND r.company_id IS NOT NULL
GROUP BY r.company_id;

GRANT SELECT ON public.public_company_aggregates TO anon, authenticated;


-- -----------------------------------------------------------------------------
-- 6. PRIVILEGED RPCS / ADMIN PATHS (sketches)
-- -----------------------------------------------------------------------------

-- 6.1 admin_set_user_role(target uuid, new_role app_role)
-- Only an admin may change a user's role. Writes a moderation_events row
-- with target_kind='profile' + event_type='role_changed'. SECURITY DEFINER
-- so the function can write to profiles.role and moderation_events
-- regardless of the caller's RLS — but the function FIRST checks the caller
-- is an admin.
CREATE OR REPLACE FUNCTION public.admin_set_user_role(
  target uuid,
  new_role app_role
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller     uuid := auth.uid();
  old_role   app_role;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO old_role FROM public.profiles WHERE id = target;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile not found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.profiles
     SET role = new_role
   WHERE id = target;

  INSERT INTO public.moderation_events (
    target_kind, target_id, actor_id, event_type,
    previous_status, new_status, metadata
  ) VALUES (
    'profile', target, caller, 'role_changed',
    old_role::text, new_role::text,
    jsonb_build_object('changed_by', caller)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_user_role(uuid, app_role) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_set_user_role(uuid, app_role)
  TO authenticated;


-- 6.2 apply_review_revision(revision_id uuid)
-- Moderator action: copy an approved revision into the live tenancy_reviews
-- row. Bypasses the freeze trigger via a session GUC. Writes a
-- review_resubmitted event.
--
-- IDEMPOTENCY (v1 hardening): the function ratchets `applied_at` on the
-- revision row in a single atomic UPDATE — only one caller wins per revision.
-- A second apply attempt (concurrent click, retry, double-fire) is rejected
-- with a clean exception instead of writing a duplicate audit event.
--
-- EXISTENCE: after acquiring the row lock on the live review, the function
-- checks FOUND. If the review was deleted between revision approval and
-- apply, the function raises rather than silently writing an audit event
-- against a non-existent target.
--
-- CONCURRENCY: the live review row is held under `FOR UPDATE` for the rest
-- of the transaction, serialising applies against the same review_id without
-- affecting other reviews.
--
-- SNAPSHOT REFRESH: `author_display_name_snapshot` is refreshed from the
-- author's current `profiles.display_name`. A tombstoned author yields the
-- tombstone marker; if the profile no longer exists the previous snapshot is
-- retained (COALESCE fallback).
CREATE OR REPLACE FUNCTION public.apply_review_revision(revision_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller        uuid := auth.uid();
  rev           public.tenancy_review_revisions;
  current_name  text;
BEGIN
  IF NOT public.is_moderator_or_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  -- Atomic claim: mark the revision as applied iff it is approved and has
  -- not been applied yet. Concurrent attempts see exactly one winner.
  UPDATE public.tenancy_review_revisions
     SET applied_at = now()
   WHERE id = revision_id
     AND status = 'approved'
     AND applied_at IS NULL
   RETURNING * INTO rev;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'revision not applicable (missing, not approved, or already applied)'
      USING ERRCODE = 'P0001';
  END IF;

  -- Lock the live review row for the rest of the transaction. PERFORM sets
  -- FOUND based on whether the SELECT matched a row; if no row matches,
  -- the review was deleted between revision approval and apply.
  PERFORM 1 FROM public.tenancy_reviews
   WHERE id = rev.review_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'review not found' USING ERRCODE = 'P0002';
  END IF;

  -- Refresh display-name snapshot from the author's current profile (which
  -- may be tombstoned). COALESCE preserves the existing snapshot if the
  -- profile row no longer exists at all.
  SELECT display_name INTO current_name
    FROM public.profiles
   WHERE id = rev.author_id;

  -- Bypass freeze trigger for this transaction.
  PERFORM set_config('rml.apply_revision', 'on', true);

  UPDATE public.tenancy_reviews
     SET overall_rating              = rev.overall_rating,
         communication_rating        = rev.communication_rating,
         contract_fairness_rating    = rev.contract_fairness_rating,
         maintenance_rating          = rev.maintenance_rating,
         location_rating             = rev.location_rating,
         monthly_rent                = rev.monthly_rent,
         deposit_amount              = rev.deposit_amount,
         deposit_returned            = rev.deposit_returned,
         mould                       = rev.mould,
         issue_categories            = rev.issue_categories,
         tenancy_start               = rev.tenancy_start,
         tenancy_end                 = rev.tenancy_end,
         general_text                = rev.general_text,
         is_high_risk                = rev.is_high_risk,
         author_display_name_snapshot = COALESCE(current_name, author_display_name_snapshot),
         last_edited_at              = now()
   WHERE id = rev.review_id;

  INSERT INTO public.moderation_events (
    target_kind, target_id, actor_id, event_type, new_status, metadata
  ) VALUES (
    'review', rev.review_id, caller, 'review_resubmitted', 'approved',
    jsonb_build_object('revision_id', rev.id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.apply_review_revision(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.apply_review_revision(uuid)
  TO authenticated;


-- -----------------------------------------------------------------------------
-- 7. PROFILE PROVISIONING & DISPLAY-NAME SNAPSHOT TRIGGERS
-- -----------------------------------------------------------------------------

-- 7.1 handle_new_auth_user ----------------------------------------------------
-- AFTER INSERT on auth.users creates a public.profiles row with a default
-- pseudonymous display name and locale.
-- Fail-closed elsewhere: privileged code paths check the profile exists.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  raw_locale      text := NEW.raw_user_meta_data ->> 'locale';
  resolved_locale text;
BEGIN
  -- Locale hardening: a `profiles.locale` CHECK constraint enforces
  -- IN ('da', 'en'). Garbage in `raw_user_meta_data` (NULL, empty string,
  -- 'fr', 'EN ', JSON injection attempts) would otherwise fail the INSERT
  -- and roll back the auth.users signup, blocking the user from creating
  -- an account. We sanitise here: empty / NULL / non-matching → 'da'.
  resolved_locale := CASE
    WHEN raw_locale IN ('da', 'en') THEN raw_locale
    ELSE 'da'
  END;

  INSERT INTO public.profiles (id, display_name, locale, role)
  VALUES (
    NEW.id,
    -- Default pseudonymous handle: short, opaque, derived from the user id.
    -- Not based on email. Users can change display_name from /account.
    -- v1: duplicates are allowed (no unique constraint); the suffix is a
    -- high-probability collision-avoider, not a guarantee.
    'user-' || substr(replace(NEW.id::text, '-', ''), 1, 8),
    resolved_locale,
    'user'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();


-- 7.2 snapshot_review_display_name (BEFORE INSERT) ----------------------------
-- Populates `tenancy_reviews.author_display_name_snapshot` from the author's
-- current pseudonymous handle at the moment of submission. This is the
-- denormalisation that decouples the public review surface from the profile
-- lifecycle (see §3.6 comments and §5.3 public_tenancy_reviews).
--
-- SECURITY: the trigger ALWAYS overwrites any value supplied by the caller.
-- An earlier draft trusted a caller-supplied non-empty value, which let any
-- authenticated user spoof the public-facing display name at submission. The
-- snapshot is now derived solely from `profiles.display_name`. Privileged
-- refresh of the snapshot (when a revision is applied) goes through
-- `apply_review_revision` (§6.2), which writes via direct UPDATE and does
-- not pass through this trigger.
--
-- If the author's profile is missing the trigger RAISEs — fail-closed,
-- preserving the NOT NULL invariant on the snapshot column.
CREATE OR REPLACE FUNCTION public.snapshot_review_display_name()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  resolved_name text;
BEGIN
  SELECT display_name INTO resolved_name
    FROM public.profiles
   WHERE id = NEW.author_id;

  IF resolved_name IS NULL THEN
    -- Fail-closed: the snapshot is required for the public view to function.
    RAISE EXCEPTION
      'cannot snapshot author display_name: profile missing for author_id %',
      NEW.author_id USING ERRCODE = 'P0001';
  END IF;

  -- Always overwrite — never trust the caller for this column.
  NEW.author_display_name_snapshot := resolved_name;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_snapshot_review_display_name ON public.tenancy_reviews;
CREATE TRIGGER tg_snapshot_review_display_name
  BEFORE INSERT ON public.tenancy_reviews
  FOR EACH ROW EXECUTE FUNCTION public.snapshot_review_display_name();


-- 7.3 INITIAL ADMIN SEEDING — manual, out-of-band (v1) ------------------------
-- No bootstrap mechanism in v1.
--
-- `admin_set_user_role` requires an existing admin to call it (§6.1's
-- is_admin() check). The first admin therefore cannot be created by the
-- platform itself. The v1 procedure is intentionally manual:
--
--   1. The maintainer signs up a normal user account through the regular
--      auth flow.
--   2. The maintainer connects to the database with a privileged role
--      (e.g. the `service_role` connection from the Supabase dashboard SQL
--      editor) and runs:
--          UPDATE public.profiles
--             SET role = 'admin'
--           WHERE id = '<the maintainer's auth.users.id>';
--   3. Subsequent admin assignments use `admin_set_user_role` and produce
--      `role_changed` events.
--
-- A production deployment checklist (separate document, not in this file)
-- must include step 2. Until step 2 is performed, the platform has no
-- privileged users and no moderation can occur.
--
-- v1 deliberately ships no bootstrap RPC, no admin-bootstrapping CLI, and no
-- side-channel — the simplest possible mechanism. A future, audited
-- bootstrap path may be considered if the manual step becomes a friction
-- point during deployments.


-- -----------------------------------------------------------------------------
-- 8. PUBLISHED-REVIEW FREEZE TRIGGER
-- -----------------------------------------------------------------------------
-- Once a tenancy_review is `approved`, edits to public-content columns are
-- rejected. The privileged path (apply_review_revision) sets the GUC
-- `rml.apply_revision = 'on'` to bypass this trigger for one transaction.
CREATE OR REPLACE FUNCTION public.tg_freeze_published_review()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('rml.apply_revision', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF OLD.moderation_status = 'approved' AND (
       NEW.overall_rating              IS DISTINCT FROM OLD.overall_rating
    OR NEW.communication_rating        IS DISTINCT FROM OLD.communication_rating
    OR NEW.contract_fairness_rating    IS DISTINCT FROM OLD.contract_fairness_rating
    OR NEW.maintenance_rating          IS DISTINCT FROM OLD.maintenance_rating
    OR NEW.location_rating             IS DISTINCT FROM OLD.location_rating
    OR NEW.monthly_rent                IS DISTINCT FROM OLD.monthly_rent
    OR NEW.deposit_amount              IS DISTINCT FROM OLD.deposit_amount
    OR NEW.deposit_returned            IS DISTINCT FROM OLD.deposit_returned
    OR NEW.mould                       IS DISTINCT FROM OLD.mould
    OR NEW.issue_categories            IS DISTINCT FROM OLD.issue_categories
    OR NEW.tenancy_start               IS DISTINCT FROM OLD.tenancy_start
    OR NEW.tenancy_end                 IS DISTINCT FROM OLD.tenancy_end
    OR NEW.general_text                IS DISTINCT FROM OLD.general_text
  ) THEN
    RAISE EXCEPTION
      'Published reviews are frozen. Submit a tenancy_review_revisions row.'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tenancy_reviews_freeze_published ON public.tenancy_reviews;
CREATE TRIGGER tenancy_reviews_freeze_published
  BEFORE UPDATE ON public.tenancy_reviews
  FOR EACH ROW EXECUTE FUNCTION public.tg_freeze_published_review();


-- -----------------------------------------------------------------------------
-- 9. APPEND-ONLY ENFORCEMENT FOR moderation_events
-- -----------------------------------------------------------------------------
-- Defensive triggers that complement the absence of UPDATE/DELETE policies.
-- Even service-role and superuser code paths that try UPDATE / DELETE /
-- TRUNCATE on this table are blocked. Removing the triggers requires its
-- own reviewed migration.
--
-- The trigger function raises unconditionally — it never returns — so it is
-- safe to reuse across ROW-level (UPDATE / DELETE) and STATEMENT-level
-- (TRUNCATE) trigger contexts.
CREATE OR REPLACE FUNCTION public.tg_moderation_events_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'moderation_events is append-only — UPDATE/DELETE/TRUNCATE forbidden.'
    USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS moderation_events_no_update ON public.moderation_events;
CREATE TRIGGER moderation_events_no_update
  BEFORE UPDATE ON public.moderation_events
  FOR EACH ROW EXECUTE FUNCTION public.tg_moderation_events_immutable();

DROP TRIGGER IF EXISTS moderation_events_no_delete ON public.moderation_events;
CREATE TRIGGER moderation_events_no_delete
  BEFORE DELETE ON public.moderation_events
  FOR EACH ROW EXECUTE FUNCTION public.tg_moderation_events_immutable();

-- TRUNCATE is statement-level, not row-level. Without this trigger, a
-- superuser, the table owner, or a misconfigured service-role tool could
-- wipe the entire audit log in one statement and bypass both the RLS-deny
-- on UPDATE/DELETE and the row-level triggers above.
DROP TRIGGER IF EXISTS moderation_events_no_truncate ON public.moderation_events;
CREATE TRIGGER moderation_events_no_truncate
  BEFORE TRUNCATE ON public.moderation_events
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_moderation_events_immutable();


-- -----------------------------------------------------------------------------
-- 10. STORAGE POLICY NOTES (drafts only — NOT applied)
-- -----------------------------------------------------------------------------
-- These are intended for the storage.objects table managed by Supabase's
-- storage extension. The drafts below match SECURITY_RULES §3 and §8.
--
-- Buckets to create (via Supabase dashboard or storage admin RPC, NOT in
-- this migration):
--
--   * review-photos          (private)  — MIME: image/jpeg, image/png,
--                                          image/webp; size ≤ 10 MB.
--   * verification-documents (private)  — MIME: application/pdf, image/jpeg,
--                                          image/png; size ≤ 15 MB.
--
-- Both buckets are PRIVATE. There is no public bucket in the product.
-- Public pages render approved review photos via short-lived signed URLs
-- minted by a server route that checks moderation_status='approved' on
-- both the photo and its parent review.
--
-- Suggested storage policies (commented out — apply in a follow-up migration
-- once the bucket names are created):
--
-- review-photos: read by the owner; read by moderators/admins; insert by
-- the owner under a user-scoped path prefix.
/*
CREATE POLICY review_photos_select_owner ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'review-photos' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY review_photos_select_moderator ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'review-photos' AND public.is_moderator_or_admin()
  );

CREATE POLICY review_photos_insert_owner ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'review-photos' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY verification_documents_select_owner ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'verification-documents' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY verification_documents_select_moderator ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'verification-documents' AND public.is_moderator_or_admin()
  );

CREATE POLICY verification_documents_insert_owner ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'verification-documents' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );
*/


-- -----------------------------------------------------------------------------
-- END OF PROPOSAL
-- -----------------------------------------------------------------------------
-- Companion review: docs/SCHEMA_REVIEW.md
