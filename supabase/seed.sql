-- =============================================================================
-- supabase/seed.sql — LOCAL DEVELOPMENT ONLY
-- =============================================================================
-- This file is automatically applied by `supabase db reset` AFTER all
-- migrations have run. It populates the local Supabase database with a
-- minimal, FICTIONAL dataset so the public views, moderation queues, and
-- account flows can be exercised by hand.
--
-- *** DO NOT use any of this in production. ***
--   - Every email is on the `@dev.local` namespace.
--   - Every CVR number starts with `99` (real Danish CVRs do not).
--   - Every company name carries the `(DEV ONLY)` suffix.
--   - Every street is a clearly fictional name (Testvej, Eksempelgade, etc.).
--   - No real person, address, or company is referenced.
--
-- Idempotency: this file is intended to run after `supabase db reset` against
-- a fresh database, so it does not strictly need ON CONFLICT clauses. We
-- include them anyway so the file can also be re-run against an existing
-- seeded DB without exploding. moderation_events has no natural unique key —
-- re-running without a reset will duplicate event rows. Always prefer
-- `supabase db reset` over re-running this file directly.
--
-- Login: this seed inserts rows into `auth.users` so that the FK chain
-- (profiles → tenancy_reviews → moderation_events) works. It does NOT
-- populate `auth.identities`, so password sign-in via Supabase Auth will
-- not yet succeed — that is intentional, since auth flow wiring is a
-- separate "Next milestones" task (see README §Next milestones). For now,
-- the seed enables READ-side browsing of public views, Studio inspection,
-- and direct-SQL exercises against the schema.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. AUTH USERS  →  profiles (via handle_new_auth_user trigger)
-- -----------------------------------------------------------------------------
-- The migration's `on_auth_user_created` trigger (§7.1) inserts a default
-- profiles row for each new auth.users row, with a placeholder display name
-- like `user-XXXXXXXX`. We then UPDATE those rows below to assign readable
-- display names and the admin role.

INSERT INTO auth.users (
  instance_id, id, aud, role, email,
  encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated',
    'admin@dev.local',
    crypt('dev-password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"locale":"da"}'::jsonb,
    now(), now(), '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000002',
    'authenticated', 'authenticated',
    'renter-aarhus@dev.local',
    crypt('dev-password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"locale":"da"}'::jsonb,
    now(), now(), '', '', '', ''
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000003',
    'authenticated', 'authenticated',
    'tenant-cph@dev.local',
    crypt('dev-password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"locale":"en"}'::jsonb,
    now(), now(), '', '', '', ''
  )
ON CONFLICT (id) DO NOTHING;

-- The trigger has now created three profiles rows with default placeholder
-- display names. Rename them and promote the first to admin.
UPDATE public.profiles
   SET display_name = 'admin-local',
       role         = 'admin'
 WHERE id = '00000000-0000-0000-0000-000000000001';

UPDATE public.profiles
   SET display_name = 'renter-aarhus'
 WHERE id = '00000000-0000-0000-0000-000000000002';

UPDATE public.profiles
   SET display_name = 'tenant-cph'
 WHERE id = '00000000-0000-0000-0000-000000000003';

-- Audit the manual admin promotion (the real path is admin_set_user_role,
-- which produces a role_changed event automatically; the seed mimics that).
INSERT INTO public.moderation_events (
  target_kind, target_id, actor_id, event_type,
  previous_status, new_status, metadata, created_at
) VALUES (
  'profile',
  '00000000-0000-0000-0000-000000000001',
  NULL,                       -- NULL actor = system / seed event
  'role_changed',
  'user', 'admin',
  '{"seed":true,"reason":"initial dev admin"}'::jsonb,
  now()
);


-- -----------------------------------------------------------------------------
-- 2. REFERENCE DATA — buildings, addresses, dwellings, companies
-- -----------------------------------------------------------------------------
-- Stable UUID prefixes per entity type, for readability while inspecting in
-- Studio: 1*=buildings, 2*=addresses, 3*=dwellings, 4*=companies.

-- Buildings -------------------------------------------------------------------
INSERT INTO public.buildings (id, bbr_building_id, build_year, building_type)
VALUES
  ('11111111-1111-1111-1111-111111111101', 'BBR-TEST-A1', 1965, 'multi-storey-apartment'),
  ('11111111-1111-1111-1111-111111111102', 'BBR-TEST-A2', 1998, 'multi-storey-apartment'),
  ('11111111-1111-1111-1111-111111111103', 'BBR-TEST-A3', 1925, 'multi-storey-apartment')
ON CONFLICT (id) DO NOTHING;

-- Addresses -------------------------------------------------------------------
-- Streets are clearly fictional: "Testvej", "Eksempelgade", "Demoallé",
-- "Prøvestien" — Danish-shaped names that do not correspond to real public
-- streets. `floor` / `door` / geo are stored but NEVER exposed by
-- public_addresses (anti-doxxing; SECURITY_RULES §10, SCHEMA_REVIEW §1.1).
INSERT INTO public.addresses (
  id, dar_address_id, street, house_number, floor, door,
  postal_code, city, building_id, geo_lat, geo_lon
) VALUES
  (
    '22222222-2222-2222-2222-222222222201', 'DAR-TEST-001',
    'Testvej', '12', '2', 'tv', '8000', 'Aarhus C',
    '11111111-1111-1111-1111-111111111101', 56.156100, 10.205700
  ),
  (
    '22222222-2222-2222-2222-222222222202', 'DAR-TEST-002',
    'Eksempelgade', '5', 'st', '3', '2200', 'København N',
    '11111111-1111-1111-1111-111111111102', 55.696500, 12.553400
  ),
  (
    '22222222-2222-2222-2222-222222222203', 'DAR-TEST-003',
    'Demoallé', '99', '1', '4', '5000', 'Odense C',
    '11111111-1111-1111-1111-111111111103', 55.395000, 10.388900
  ),
  (
    '22222222-2222-2222-2222-222222222204', 'DAR-TEST-004',
    'Prøvestien', '7', NULL, NULL, '9000', 'Aalborg',
    NULL, 57.048800, 9.921800
  )
ON CONFLICT (id) DO NOTHING;

-- Dwellings -------------------------------------------------------------------
INSERT INTO public.dwellings (id, address_id, bbr_dwelling_id, area_m2, rooms)
VALUES
  ('33333333-3333-3333-3333-333333333301', '22222222-2222-2222-2222-222222222201', 'BBR-DW-TEST-001', 62.5, 2.0),
  ('33333333-3333-3333-3333-333333333302', '22222222-2222-2222-2222-222222222202', 'BBR-DW-TEST-002', 41.0, 1.0),
  ('33333333-3333-3333-3333-333333333303', '22222222-2222-2222-2222-222222222203', 'BBR-DW-TEST-003', 85.0, 3.0)
ON CONFLICT (id) DO NOTHING;

-- Companies -------------------------------------------------------------------
-- CVR numbers start with '99' to be obviously fictional (real Danish CVR
-- numbers do not). Each company name carries the (DEV ONLY) suffix.
INSERT INTO public.companies (id, cvr_number, name, company_type, status)
VALUES
  (
    '44444444-4444-4444-4444-444444444401', '99000001',
    'TestRental ApS (DEV ONLY)', 'rental', 'active'
  ),
  (
    '44444444-4444-4444-4444-444444444402', '99000002',
    'Eksempel Boligadministration A/S (DEV ONLY)', 'administration', 'active'
  ),
  (
    '44444444-4444-4444-4444-444444444403', '99000003',
    'Demo Ejendomme ApS (DEV ONLY)', 'rental', 'dissolved'
  )
ON CONFLICT (id) DO NOTHING;


-- -----------------------------------------------------------------------------
-- 3. TENANCY REVIEWS
-- -----------------------------------------------------------------------------
-- The BEFORE INSERT snapshot trigger (tg_snapshot_review_display_name)
-- populates `author_display_name_snapshot` from profiles.display_name. The
-- column is NOT NULL but we pass the empty string and let the trigger
-- overwrite it (the trigger now ALWAYS overwrites — see migration §7.2).

-- Review #1 — APPROVED, COMPANY-LINKED ----------------------------------------
-- Author: renter-aarhus. Aarhus address. Full deposit return, no mould.
-- Appears in public_tenancy_reviews and the Aarhus address's aggregates.
INSERT INTO public.tenancy_reviews (
  id, author_id, address_id, dwelling_id, company_id,
  author_display_name_snapshot,
  overall_rating, communication_rating, contract_fairness_rating,
  maintenance_rating, location_rating,
  monthly_rent, deposit_amount, deposit_returned, mould,
  issue_categories, tenancy_start, tenancy_end, general_text,
  moderation_status, verification_status, is_high_risk,
  submitted_at, published_at
) VALUES (
  '55555555-5555-5555-5555-555555555501',
  '00000000-0000-0000-0000-000000000002',
  '22222222-2222-2222-2222-222222222201',
  '33333333-3333-3333-3333-333333333301',
  '44444444-4444-4444-4444-444444444401',
  '',  -- overwritten by trigger
  4, 4, 5, 4, 5,
  9500.00, 28500.00, 'full', 'none',
  ARRAY[]::text[],
  '2023-06-01', '2025-03-31',
  'Local-dev sample review. Pleasant tenancy; full deposit returned within four weeks of move-out.',
  'approved', 'verified', false,
  now() - interval '7 days', now() - interval '5 days'
)
ON CONFLICT (id) DO NOTHING;

-- Review #2 — APPROVED, ADDRESS-ONLY (private landlord) -----------------------
-- Author: tenant-cph. Copenhagen address. Partial deposit, minor mould.
-- `company_id = NULL` represents a private individual landlord — no public
-- profile is created for them (PRODUCT_DECISIONS §10). The review attaches
-- to the address only.
INSERT INTO public.tenancy_reviews (
  id, author_id, address_id, dwelling_id, company_id,
  author_display_name_snapshot,
  overall_rating, communication_rating, contract_fairness_rating,
  maintenance_rating, location_rating,
  monthly_rent, deposit_amount, deposit_returned, mould,
  issue_categories, tenancy_start, tenancy_end, general_text,
  moderation_status, verification_status, is_high_risk,
  submitted_at, published_at
) VALUES (
  '55555555-5555-5555-5555-555555555502',
  '00000000-0000-0000-0000-000000000003',
  '22222222-2222-2222-2222-222222222202',
  '33333333-3333-3333-3333-333333333302',
  NULL,
  '',
  3, 3, 4, 2, 4,
  11200.00, 22400.00, 'partial', 'minor',
  ARRAY['heating', 'damp']::text[],
  '2022-09-01', '2024-08-31',
  'Local-dev sample review. Some maintenance delays during winter; partial deposit return after itemised deductions.',
  'approved', 'unverified', false,
  now() - interval '14 days', now() - interval '10 days'
)
ON CONFLICT (id) DO NOTHING;

-- Review #3 — PENDING ---------------------------------------------------------
-- Author: renter-aarhus. Odense address. Ongoing tenancy (tenancy_end NULL).
-- In moderation queue; NOT in any public view.
INSERT INTO public.tenancy_reviews (
  id, author_id, address_id, dwelling_id, company_id,
  author_display_name_snapshot,
  overall_rating, communication_rating, contract_fairness_rating,
  maintenance_rating, location_rating,
  monthly_rent, deposit_amount, deposit_returned, mould,
  issue_categories, tenancy_start, tenancy_end, general_text,
  moderation_status, verification_status, is_high_risk,
  submitted_at
) VALUES (
  '55555555-5555-5555-5555-555555555503',
  '00000000-0000-0000-0000-000000000002',
  '22222222-2222-2222-2222-222222222203',
  '33333333-3333-3333-3333-333333333303',
  '44444444-4444-4444-4444-444444444402',
  '',
  2, 2, 3, 3, 5,
  8200.00, 16400.00, 'pending', 'none',
  ARRAY['noise']::text[],
  '2024-01-01', NULL,
  'Local-dev sample review submitted but not yet approved.',
  'pending', 'unverified', false,
  now() - interval '2 days'
)
ON CONFLICT (id) DO NOTHING;

-- Review #4 — REJECTED, HIGH-RISK FLAG ----------------------------------------
-- Author: tenant-cph. Aalborg address (no building, no dwelling — tests the
-- nullable FK chain). High-risk flag set. NOT in any public view.
INSERT INTO public.tenancy_reviews (
  id, author_id, address_id, dwelling_id, company_id,
  author_display_name_snapshot,
  overall_rating, communication_rating, contract_fairness_rating,
  maintenance_rating, location_rating,
  monthly_rent, deposit_amount, deposit_returned, mould,
  issue_categories, tenancy_start, tenancy_end, general_text,
  moderation_status, verification_status, is_high_risk,
  submitted_at
) VALUES (
  '55555555-5555-5555-5555-555555555504',
  '00000000-0000-0000-0000-000000000003',
  '22222222-2222-2222-2222-222222222204',
  NULL,
  '44444444-4444-4444-4444-444444444403',
  '',
  1, 1, 1, 1, 2,
  7500.00, 15000.00, 'none', 'significant',
  ARRAY['pests', 'unresponsive_landlord']::text[],
  '2021-03-01', '2022-12-31',
  'Local-dev sample free text flagged as high-risk and subsequently rejected by moderation.',
  'rejected', 'unverified', true,
  now() - interval '21 days'
)
ON CONFLICT (id) DO NOTHING;


-- -----------------------------------------------------------------------------
-- 4. MODERATION EVENTS — lifecycle history per review
-- -----------------------------------------------------------------------------
-- Each review carries its lifecycle: 'submitted' (always), plus the eventual
-- decision ('approved' / 'rejected' / 'removed') where applicable. The
-- moderation_events table is append-only (RLS denies UPDATE/DELETE + a
-- defensive trigger). The seed only INSERTs, so it does not break the
-- invariant.

INSERT INTO public.moderation_events (
  target_kind, target_id, actor_id, event_type, reason,
  previous_status, new_status, metadata, created_at
) VALUES
  -- Review #1: submitted → approved
  (
    'review', '55555555-5555-5555-5555-555555555501',
    '00000000-0000-0000-0000-000000000002', 'submitted',
    'user submission', NULL, 'pending',
    '{"seed":true}'::jsonb, now() - interval '7 days'
  ),
  (
    'review', '55555555-5555-5555-5555-555555555501',
    '00000000-0000-0000-0000-000000000001', 'approved',
    'meets policy', 'pending', 'approved',
    '{"seed":true}'::jsonb, now() - interval '5 days'
  ),

  -- Review #2: submitted → approved
  (
    'review', '55555555-5555-5555-5555-555555555502',
    '00000000-0000-0000-0000-000000000003', 'submitted',
    'user submission', NULL, 'pending',
    '{"seed":true}'::jsonb, now() - interval '14 days'
  ),
  (
    'review', '55555555-5555-5555-5555-555555555502',
    '00000000-0000-0000-0000-000000000001', 'approved',
    'meets policy', 'pending', 'approved',
    '{"seed":true}'::jsonb, now() - interval '10 days'
  ),

  -- Review #3: submitted (still pending)
  (
    'review', '55555555-5555-5555-5555-555555555503',
    '00000000-0000-0000-0000-000000000002', 'submitted',
    'user submission', NULL, 'pending',
    '{"seed":true}'::jsonb, now() - interval '2 days'
  ),

  -- Review #4: submitted → rejected (with high-risk flag)
  (
    'review', '55555555-5555-5555-5555-555555555504',
    '00000000-0000-0000-0000-000000000003', 'submitted',
    'user submission', NULL, 'pending',
    '{"seed":true,"is_high_risk":true}'::jsonb, now() - interval '21 days'
  ),
  (
    'review', '55555555-5555-5555-5555-555555555504',
    '00000000-0000-0000-0000-000000000001', 'rejected',
    'unverifiable criminal accusation against a named individual',
    'pending', 'rejected',
    '{"seed":true}'::jsonb, now() - interval '20 days'
  );


-- =============================================================================
-- Notes about what this seed deliberately does NOT do:
--
--   * No photos. The `review-photos` storage bucket is not created yet
--     (`docs/SCHEMA_REVIEW.md` open question + README current-limitations).
--   * No verification documents. Same reason — `verification-documents`
--     bucket does not exist yet.
--   * No company replies. The `replies_insert_disabled` RLS policy holds
--     in v1 (PRODUCT_DECISIONS §9) and the table has zero rows by design.
--   * No reports. Reporting flows are not yet wired.
--   * No auth.identities rows. Password sign-in via Supabase Auth is not
--     enabled here — see the file header.
-- =============================================================================
