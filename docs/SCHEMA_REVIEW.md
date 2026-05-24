# Schema review — v1 proposal

Companion to [`supabase/migrations/20260524000000_schema_v1_proposal.sql`](../supabase/migrations/20260524000000_schema_v1_proposal.sql).

This document is a **review draft**. The migration file is **not applied** to
any environment. The purpose is to circulate the data model, RLS, public-view,
and trigger strategy for human review before a real migration is created and
the database stops being a blank slate.

**v1 status:** the eleven major design choices that gated the first draft
have been resolved with explicit, documented decisions (§1 below). A static
review pass then identified four critical bugs and six important hardening
gaps; all ten have been addressed in the SQL (see §1.12 for the hardening
summary and §9 for the much-trimmed still-open list). The proposal is now
safe for local apply / testing.

Read together with the binding governance:

- [`docs/DATA_MODEL.md`](DATA_MODEL.md) — entities, public vs private, audit.
- [`docs/SECURITY_RULES.md`](SECURITY_RULES.md) — RLS, storage, roles, profile provisioning, public-read pattern, append-only enforcement.
- [`docs/MODERATION_POLICY.md`](MODERATION_POLICY.md) — pre-publication moderation, review freezing, event log.
- [`docs/PRODUCT_DECISIONS.md`](PRODUCT_DECISIONS.md) — companies vs private landlords, deferred reply mechanism, open questions.
- [`docs/DESIGN_PRINCIPLES.md`](DESIGN_PRINCIPLES.md) — moderation visibility, verification badge, anti-doxxing in the UI.
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — layering (`server/repositories/` reads through `public_*` views).

---

## 1. Resolved v1 decisions

The following are **binding for v1**. They are reflected in the SQL draft and
in the comments throughout the migration. Reopening one of them is a new
governance change, not a routine schema tweak.

### 1.1 Address-detail public exposure — withhold by default

Public-facing views must **not** expose information that can isolate a single
household. `public_addresses` exposes only:

- street name (`street`)
- street number (`house_number`)
- postcode (`postal_code`)
- city (`city`)
- and the structural `id` + `building_id` for joins.

It deliberately **does not** expose:

- `floor` — frequently identifies a single unit per building.
- `door` — directly identifies a single apartment.
- `geo_lat` / `geo_lon` — pin-precise location.
- any dwelling/unit identifier — by extension.

These columns continue to exist on the base `addresses` and `dwellings` tables
so that moderation, verification, tenancy linkage, and anti-abuse workflows
can disambiguate units internally. Re-exposing any of them publicly requires
a new product decision and a follow-up migration.

**Rationale.** RML publishes statements about identifiable parties. Public
fields that triangulate to a single household convert the platform into a
doxxing surface, especially for reviews involving private individual
landlords where a single occupant equals a single person. Withholding by
default is the only safe v1 posture.

### 1.2 Company replies — deferred

The `company_replies` table is created in the schema, but its public-facing
write path is **disabled** in v1:

- `replies_insert_disabled` RLS policy has `WITH CHECK (false)` (§4.10 of the
  migration).
- No company-representative verification mechanism is designed in v1 (the
  `company_representatives` table is deliberately not modelled).
- `public_company_replies` is defined for forward compatibility but returns
  zero rows in v1 because no reply can reach `moderation_status = 'approved'`.

Enabling replies later is a *policy* change (replace the `false` policy
+ add a representative table or service-role path), not a base-schema change.

### 1.3 Verification badge — minimal public signal only

Approved public reviews **may** expose a simple `verification_status`
state (`unverified | pending_verification | verified | verification_failed`)
via `public_tenancy_reviews`. The view exposes **nothing** else about the
underlying evidence:

- no `document_type`,
- no `storage_path`,
- no evidence-review timestamps,
- no JOIN to `verification_documents` of any kind.

The UI treats the field as a small text-and-icon badge
(`docs/DESIGN_PRINCIPLES.md` §4.2). Verification remains intentionally
privacy-preserving.

### 1.4 Verification-document retention — 90 days default

`verification_documents.retention_expires_at` has a **default of `now() +
90 days`** at insert. Retention is *paused or extended* (the sweeper job
refuses to delete) when any of the following is active:

- an open `reports` row referencing the document's review,
- a report `under_review`,
- a `legal_hold = true` flag on the document,
- a moderation escalation (recorded in `moderation_events`).

**This is a policy default, not full automation.** The retention sweeper
job is **not implemented in v1**. v1 ships:

- the default value,
- a `legal_hold` boolean (defaults to `false`),
- a partial index on `retention_expires_at WHERE legal_hold = false` so
  the sweeper can scan efficiently later.

The sweeper must, when implemented:

- write a `moderation_events` row (`evidence_accessed` or a new
  `evidence_purged` event type) on each deletion,
- remove the storage object via the storage admin client, then delete the
  row,
- never act on rows where `legal_hold = true` or where a related report is
  open / under review.

### 1.5 Display names — duplicates allowed

The `profiles` table does **not** carry a uniqueness constraint on
`display_name`. The previous `profiles_display_name_lower_uidx` index has
been removed.

**Rationale.**

- Pseudonymity is the design goal (`docs/PRODUCT_DECISIONS.md` §2,
  `docs/DESIGN_PRINCIPLES.md` §1). Enforcing global uniqueness pressures
  users toward real-name handles and creates a name-squatting surface.
- The default `user-XXXXXXXX` opaque handle produced by the provisioning
  trigger gives high-probability uniqueness without a constraint.
- Display-name lookup is not a primary access pattern; the UI identifies
  users by display_name + the page they're attached to.

### 1.6 Author-per-address uniqueness — NOT enforced at the DB layer

The database accepts multiple reviews from the same author at the same
address. A unique constraint at the DB layer would produce false positives
for legitimate cases:

- couples sharing a tenancy,
- sequential roommates,
- sublets,
- repeat tenancies (same person renting the same address years apart).

Service-layer logic in `server/services/reviews/` may enforce a softer rule
("one active *pending* review per author per address") if abuse patterns
emerge. The DB stays permissive.

### 1.7 `reports.reporter_id` and `resolved_by` — ON DELETE SET NULL

Both columns are `ON DELETE SET NULL`. The report content (reason, details,
target, decision) is part of the moderation record and remains operationally
useful after the reporter or moderator deletes their account. Erasing the
identity link is the GDPR-erasure step; the moderation row stays.

A cryptographic identifier (HMAC of user_id, etc.) was considered as an
alternative for retroactive integrity checks. It is **not adopted in v1** —
the operational benefit is small relative to the key-management work it
introduces.

### 1.8 `moderation_events` — polymorphic single table, kept

The polymorphic `(target_kind, target_id)` design is kept for v1. The
tradeoff is documented inline in the SQL:

- **Pro:** one queryable audit log, one append-only invariant, one set of
  triggers and policies; adding a new target_kind is additive.
- **Con:** PostgreSQL cannot enforce a FK on `target_id`. A buggy service
  could insert an event with a non-existent target.

**v1 mitigations:** all inserts go through typed helpers in
`server/services/moderation/` that look up the target row before logging,
and the `target_kind` CHECK enumerates legal kinds so typos cannot pass. A
non-binding `validate_moderation_target(kind, id)` SQL function may be
added in a follow-up migration as structural defence (still-open question
in §9).

### 1.9 `apply_review_revision` — SELECT … FOR UPDATE on the live row

The function now locks the live `tenancy_reviews` row with `SELECT … FOR
UPDATE` before applying the revision. Rationale:

- The freeze-bypass GUC (`rml.apply_revision`) is per-transaction. Two
  concurrent applies for the same review could interleave and produce an
  inconsistent snapshot.
- The row lock also gives a stable read for the display-name snapshot
  refresh, which is part of the same statement.
- Concurrency on *different* reviews is unaffected; the lock is per-row.

### 1.10 Initial admin — manual, out-of-band

v1 ships no bootstrap RPC, no admin-CLI, and no side-channel. The first
admin is created by a manual SQL `UPDATE` against `profiles.role`
executed via a privileged connection (Supabase dashboard SQL editor or a
service-role psql session). The production deployment checklist must
include this step.

Subsequent admin assignments use `admin_set_user_role` (which produces a
`role_changed` event). The platform has no privileged users until the
manual bootstrap is performed.

### 1.11 Deleted profiles — tombstone + denormalised snapshot

Approved public reviews remain visible after account deletion. The schema
implements this via two complementary mechanisms:

1. **Tombstone in `profiles`.** A `deleted_at timestamptz` column marks a
   soft-deleted profile. The recommended deletion flow anonymises the
   `display_name` to a neutral marker (e.g. `[Deleted user]` — exact
   localisation TBD, see §9) and sets `deleted_at = now()`. The row
   stays.
2. **Denormalised display name on reviews.** `tenancy_reviews` carries
   `author_display_name_snapshot text NOT NULL`, populated at submission
   by trigger (`tg_snapshot_review_display_name`) and refreshed inside
   `apply_review_revision`. The public view reads this column directly
   (no JOIN to `profiles`).

FK chains downstream of `profiles` use `ON DELETE SET NULL` so that even
if the profile is hard-deleted (cascade from `auth.users` → `profiles`),
the public review survives with `author_id = NULL` and the snapshot
intact:

- `tenancy_reviews.author_id` → SET NULL.
- `tenancy_review_revisions.author_id`, `.decided_by` → SET NULL.
- `review_photos.uploader_id` → SET NULL.
- `verification_documents.uploader_id` → SET NULL.
- `reports.reporter_id`, `.resolved_by` → SET NULL.
- `moderation_events.actor_id` → SET NULL.
- `company_replies.author_id` → SET NULL.

`company_replies.author_id` is also SET NULL so that, when the reply
mechanism is enabled in a later version, deletions behave consistently.

### 1.12 Hardening pass (resolved review findings)

The first static review of the migration identified four critical bugs (C-1
through C-4) and six important hardening gaps (I-1 through I-6). All ten
are addressed in the SQL. Summary:

| Finding | What was wrong | What changed |
| --- | --- | --- |
| **C-1** | `reports` referenced `company_replies(id)` inline before the latter existed — migration would error on first apply. | `company_replies` (§3.11) is now created before `reports` (§3.12). |
| **C-2** | `tg_snapshot_review_display_name` trusted a caller-supplied value, letting any authenticated user spoof their public display name at submission. | Trust-caller branch removed; the trigger always overwrites the snapshot from `profiles.display_name`. |
| **C-3** | No column-level GRANTs on `profiles` — combined with `profiles_update_self_limited`, any user could `UPDATE … SET role='admin'`. | `REVOKE UPDATE … FROM authenticated; GRANT UPDATE (display_name, locale) …`. `role` / `deleted_at` are now only mutable via admin RPC or service-role. |
| **C-4** | No column-level GRANTs on `tenancy_reviews` — the snapshot column was outside the freeze trigger, so authors could rewrite their display name on a *published* review. | `REVOKE UPDATE …` + column-scoped GRANT. The snapshot column is structurally read-only to authenticated. |
| **I-1** | `apply_review_revision` did not check FOUND after `SELECT … FOR UPDATE`, so a deleted-mid-flight review left a moderation event pointing nowhere. | Added `IF NOT FOUND THEN RAISE 'review not found'` after the lock. |
| **I-2** | `apply_review_revision` was non-idempotent — concurrent / retried applies wrote duplicate audit rows. | New `tenancy_review_revisions.applied_at` column, ratcheted atomically by `UPDATE … WHERE applied_at IS NULL RETURNING …` at function entry; only one caller wins. |
| **I-3** | `moderation_events` was protected against UPDATE / DELETE but not against `TRUNCATE`. | Added a `BEFORE TRUNCATE … FOR EACH STATEMENT` trigger reusing the existing immutable function. |
| **I-4** | `handle_new_auth_user` would fail signup if `raw_user_meta_data.locale` was anything other than `da` / `en`. | Locale is now sanitised — anything not in `('da', 'en')` (including NULL, empty string, JSON injection attempts) falls back to `'da'`. |
| **I-5** | `is_moderator_or_admin()` and `is_admin()` had no explicit EXECUTE grants — hardened Supabase setups that drop default PUBLIC grants would silently break the RLS policies. | Explicit `REVOKE ALL … FROM public` + `GRANT EXECUTE … TO anon, authenticated`. |
| **I-6** | `tenancy_review_revisions`, `review_photos`, and `verification_documents` had the same column-grant gap as profiles/reviews. | All three now `REVOKE UPDATE … FROM anon, authenticated;` with narrow GRANTs (content-only on revisions; caption-only on photos; nothing on verification documents — its `evidence_update_uploader` policy is dormant by design). |

Three minor cleanups were also applied while the file was open:

- The unused `citext` extension was removed.
- A partial index `WHERE deleted_at IS NOT NULL` was added to `profiles` for tombstone-cleanup queries.
- The published-recency partial index now also requires `published_at IS NOT NULL` so the index never holds NULL keys.

---

## 2. Entities and relationships

```
auth.users (Supabase)
   └── 1:1 → profiles                              (id = auth.users.id; tombstone via deleted_at)
                  └─< tenancy_reviews (author_id, ON DELETE SET NULL)
                        ├── address_id   → addresses
                        ├── dwelling_id  → dwellings   (nullable)
                        ├── company_id   → companies   (nullable; NULL = private landlord)
                        ├── author_display_name_snapshot   (denormalised — survives author deletion)
                        ├─< review_photos
                        ├─< verification_documents
                        ├─< tenancy_review_revisions
                        ├─< company_replies            (DEFERRED in v1)
                        └─< reports

addresses
   ├── building_id  → buildings                        (nullable; reference data)
   └── 1:N dwellings

moderation_events  — append-only, polymorphic
                     target_kind ∈ {review, reply, photo, report, document, profile}
                     actor_id ON DELETE SET NULL
                     never UPDATE/DELETE (RLS + defensive trigger).
```

### Reference vs user-generated

- **Reference data:** `buildings`, `addresses`, `dwellings`, `companies`. Populated later by the DAR/BBR/CVR import pipeline (`docs/ARCHITECTURE.md` §7). Reviews never *write* these — only link to them.
- **User-generated:** everything else. RLS is the authorisation boundary; the structural split between public-safe and private-but-author-only columns is enforced by the `public_*` views.

### Polymorphism notes

- `moderation_events.target_kind` + `target_id` is polymorphic (no enforced FK). See §1.8 for the tradeoff. Inserts go through typed helpers.
- `reports.review_id` / `reports.reply_id` is an XOR pair (CHECK constraint). One report targets one entity; never both, never neither.

---

## 3. Public vs private data separation

The hard rule (binding, `docs/SECURITY_RULES.md` §9): the `anon` role does **not** receive direct `SELECT` on any base table that mixes public and private columns. Public reads go through `public_*` views.

### Views created

| View | Source | Filters | Exposes |
| --- | --- | --- | --- |
| `public_addresses` | `addresses` | (none) | id, street, house_number, postal_code, city, building_id. **NEVER** floor / door / geo / unit identifiers (§1.1). |
| `public_companies` | `companies` | (none — CVR data is already public) | id, cvr_number, name, company_type, status. |
| `public_tenancy_reviews` | `tenancy_reviews` (no JOIN — uses snapshot column) | `moderation_status = 'approved'` | structured ratings + factual fields, `verification_status` (state only — §1.3), `published_at`, `last_edited_at`, `is_edited`, denormalised `author_display_name`. **Never** `author_id`. |
| `public_review_photos` | `review_photos` ⨝ `tenancy_reviews` | both rows `approved` | id, review_id, `storage_path`, caption, created_at. The route handler mints a short-lived signed URL from `storage_path`. |
| `public_company_replies` | `company_replies` | `moderation_status = 'approved'` | id, review_id, company_id, snapshot display_name, body, published_at. **Empty in v1** by construction. |
| `public_address_aggregates` | `tenancy_reviews` | approved | per-address: count, avg rating, latest published date. |
| `public_company_aggregates` | `tenancy_reviews` | approved AND `company_id NOT NULL` | per-company: count, avg rating, latest published date. |

Views run with the privileges of their owner (Postgres default — not opted into `security_invoker=true`). The owner is the role that creates them (`postgres` in Supabase) which has SELECT on the base tables, while `anon` is granted SELECT only on the view. Filtering to `moderation_status = 'approved'` is what enforces the security boundary.

### What is deliberately not in any public view

- `author_id`, `uploader_id`, `reporter_id`, `actor_id` (link to real identity).
- `moderation_status`, `is_high_risk`, `submitted_at`, internal moderation timestamps.
- `verification_documents.*` (entire table is private).
- `moderation_events.*` (private to moderators/admins).
- `reports.*` (private to reporter + moderators).
- Address `floor`, `door`, `geo_lat`, `geo_lon`, dwelling identifiers (§1.1).
- Verification evidence details — only the `verification_status` enum value is public (§1.3).

---

## 4. RLS strategy

Every table has RLS enabled. The pattern is consistent:

| Pattern | Applied to |
| --- | --- |
| Authenticated owner reads + writes own rows | `tenancy_reviews`, `tenancy_review_revisions`, `review_photos`, `verification_documents`, `reports` |
| Authenticated read all (reference data) | `buildings`, `addresses`, `dwellings`, `companies` |
| Self-read; moderator/admin read all; admin-only role write via RPC | `profiles` |
| Moderator/admin read + insert; no UPDATE/DELETE policies + defensive trigger | `moderation_events` |
| Read-self + read-moderator; insert disabled by placeholder policy | `company_replies` (deferred per §1.2) |

Helper functions used inside policies:

- `is_moderator_or_admin()` — `SECURITY DEFINER STABLE` reader of `profiles.role`.
- `is_admin()` — same, but matches `'admin'` only. Used by `admin_set_user_role`.

Both are marked `STABLE` so the planner caches results within a statement, and `SECURITY DEFINER` so they don't trip over the caller's own RLS on `profiles`.

### Where the RLS guarantees stop

- Service-role code bypasses RLS. The append-only invariant on `moderation_events` is therefore enforced *additionally* by triggers (§9 of the migration). The freeze invariant relies on the application not setting `rml.apply_revision = 'on'` outside `apply_review_revision`.
- The placeholder `replies_insert_disabled` policy on `company_replies` (always `false`) blocks any user from writing replies until the company-representative mechanism is approved. Service-role can still write; in v1 nothing writes.

---

## 5. Moderation workflow

```
Author submits review
   → INSERT tenancy_reviews   (moderation_status='pending', submitted_at=now())
       ↳ tg_snapshot_review_display_name fires → snapshot set from profiles
   → INSERT moderation_events (target_kind='review', event_type='submitted')

Moderator approves
   → UPDATE tenancy_reviews   (moderation_status='approved', published_at=now())
   → INSERT moderation_events (target_kind='review', event_type='approved')

Moderator rejects
   → UPDATE tenancy_reviews   (moderation_status='rejected')
   → INSERT moderation_events (target_kind='review', event_type='rejected')

Author proposes edit to approved review
   → INSERT tenancy_review_revisions (status='pending', author_id=auth.uid())
   → (one pending revision per review — partial UNIQUE index enforces this)
   → INSERT moderation_events (target_kind='review', event_type='review_resubmitted')

Moderator approves revision
   → UPDATE tenancy_review_revisions (status='approved', decided_by=auth.uid())
   → CALL apply_review_revision(revision_id)
        → is_moderator_or_admin() check
        → SELECT … FOR UPDATE on tenancy_reviews row
        → refresh author_display_name_snapshot from current profile
        → sets rml.apply_revision='on' (bypasses freeze trigger)
        → UPDATE tenancy_reviews (last_edited_at=now(), public fields ← revision)
        → INSERT moderation_events (event_type='review_resubmitted', new_status='approved')

Removal after publication
   → UPDATE tenancy_reviews   (moderation_status='removed')
   → INSERT moderation_events (event_type='removed')

Public reader on /address/[id]
   → SELECT * FROM public_tenancy_reviews WHERE address_id = $1 …
   → only rows with moderation_status='approved' are visible
   → no JOIN to profiles — snapshot is read directly
   → no path exists for anon to read base tenancy_reviews
```

Photos, replies (when enabled), and reports have their own pending-cycle equivalents and write matching `moderation_events` rows.

---

## 6. Review freezing / revisions

Implementation of `docs/DATA_MODEL.md` §3.1 and `docs/MODERATION_POLICY.md` §1.1.

- An `approved` review's **public-content columns** are frozen against direct UPDATE by `tg_freeze_published_review`.
- The trigger checks `current_setting('rml.apply_revision', true)` for a per-transaction bypass. Only the SECURITY DEFINER function `apply_review_revision(revision_id)` sets that GUC, and only after verifying the caller is a moderator/admin and the revision is `approved`. The bypass is therefore narrow.
- `tenancy_review_revisions` is the *workspace*: the author can edit the proposed revision while it is `pending`. Moderators review it like a new submission.
- A partial unique index enforces that only one `pending` revision exists per review at a time.
- `apply_review_revision` (§1.9 + §1.12 I-1/I-2):
  - ratchets `tenancy_review_revisions.applied_at` atomically with `UPDATE … WHERE applied_at IS NULL RETURNING …` so a duplicate / concurrent apply is rejected cleanly;
  - acquires a `SELECT … FOR UPDATE` lock on the live review row and raises if the review was deleted between revision approval and apply.
- The lifecycle event `review_resubmitted` covers both the submission and application stages.
- The view exposes a stable `is_edited` flag derived from `last_edited_at`, so the public UI can show the "edited" label without leaking the revision history (`docs/DESIGN_PRINCIPLES.md` §4.3).

What is **not** modelled in v1:

- **Per-field revision history**: we snapshot the whole proposed version on each revision row rather than diffing per field. Diff display is a UI concern.
- **Cross-version photo identity**: a photo added/removed in a revision goes through its own `review_photos` lifecycle; revisions do not own photo rows.

---

## 7. Account deletion / tombstone strategy

v1 implements the tombstone approach described in §1.11. The mechanism is
spread across three places in the schema:

1. **`profiles.deleted_at timestamptz`** — soft-delete marker. The
   recommended deletion flow updates the profile *first* (anonymises
   `display_name`, sets `deleted_at`), preserving the row.
2. **`tenancy_reviews.author_display_name_snapshot text NOT NULL`** —
   denormalised display name set at submission and refreshed at
   revision-apply. The public view reads this column directly.
3. **`ON DELETE SET NULL`** on every author-linked FK that points to
   `profiles`. If a hard cascade ever does propagate from `auth.users` →
   `profiles`, the artefacts (reviews, photos, evidence, events) survive
   with the FK nulled out.

### Deletion flow (recommended, not yet implemented)

```
delete_account_RPC()
  REQUIRE auth.uid() = self
  UPDATE profiles
     SET display_name = '[deleted-user]',
         deleted_at  = now()
   WHERE id = auth.uid();
  INSERT INTO moderation_events
    (target_kind, target_id, event_type, reason)
  VALUES
    ('profile', auth.uid(), 'role_changed', 'self-deletion');
  -- The `auth.users` row may be retained, banned, or hard-deleted via
  -- service-role at the operator's discretion. Cascade is safe in either
  -- case because of the SET NULL chain above.
```

### What the public reader sees

- For a tombstoned-but-still-present profile: the review's snapshot is
  whatever was captured at submission (unchanged by tombstoning).
- For a hard-cascaded profile: the review still renders; `author_id` is
  NULL behind the scenes; the snapshot is unchanged.
- The "edited" label still works because it depends on
  `tenancy_reviews.last_edited_at`, not on the profile.

### Localisation note

The exact tombstone string (`[deleted-user]` vs `[bruger slettet]` vs a
neutral identifier resolved in the UI) is **deferred** to product (§9).
The snapshot column stores whatever the deletion flow writes, so the
choice is contained.

---

## 8. Storage / signed-URL strategy (notes)

`SECURITY_RULES.md` §3 is binding: no public Supabase buckets.

The migration includes commented-out storage policy drafts (§10 of the SQL).
Bucket creation is **not** part of this SQL — buckets are created via the
Supabase dashboard or a storage admin RPC and the policies are applied in a
follow-up migration once the bucket names exist.

Planned buckets (both private):

- `review-photos` — `image/jpeg | image/png | image/webp`, ≤ 10 MB. Paths: `<auth.uid()>/reviews/<review_id>/<file>`.
- `verification-documents` — `application/pdf | image/jpeg | image/png`, ≤ 15 MB. Paths: `<auth.uid()>/verification/<review_id>/<file>`.

Public pages render review photos via short-lived signed URLs minted by a server route. The route reads `public_review_photos` (which already filters to approved-on-approved), then calls Supabase Storage's signed-URL API. Anon never receives a long-lived URL, and never a URL for a verification document under any circumstance.

---

## 9. Still-open questions

After the hardening pass (§1.12), all I-series items are resolved. The
remaining list is shorter and *operational* — each item below is something
that does not gate the v1 schema being applied.

1. **`validate_moderation_target(kind, id)` SQL helper** — non-binding structural check for the polymorphic `moderation_events.target_id`. Useful but optional; add in a follow-up migration if drift is observed in dev.
2. **`moderation_event_type` shape for removals** — keep the single `removed` value with a structured `metadata` jsonb breakdown (current draft), or split into `removed_by_report` / `removed_by_takedown` enum values. The metadata path is cheaper to extend; the enum path is more queryable.
3. **Tombstone display-name string** — `[deleted-user]` vs locale-aware translation vs an opaque identifier the UI resolves. The schema is agnostic; product decides what the deletion flow writes.
4. **Retention sweeper job** — not implemented. `verification_documents.retention_expires_at` and `legal_hold` are wired; the sweeper itself (scheduling, scope, audit-row writing) is a separate deliverable. Until it exists, evidence accumulates indefinitely past 90 days.
5. **`evidence_purged` event type** — new value on `moderation_event_type` for the sweeper; not added yet because the sweeper does not exist.
6. **`apply_review_revision` race against author edits** — the function ratchets `applied_at` and locks the live review row, so concurrent applies are safe. Still open: whether to also block the rare case of a moderator approving a revision while the author is actively editing it. This is most naturally a service-layer concern (advisory lock or status re-check at approval), not a DB constraint.
7. **First-admin bootstrap path** — manual `UPDATE` is the v1 mechanism. Open whether to add an audited bootstrap RPC if deployments become frequent enough to make the manual step a friction point.
8. **DAR / BBR / CVR seeding** — reference tables have no application write path. Until the import pipeline lands, populating them for development requires either a seed script (service-role) or a separate `dev-seed` migration. v1 punts on this.

That's it. Eight remaining questions, none of which block applying the
migration.

---

## 10. Known tradeoffs

- **Polymorphic FK on `moderation_events`** — no DB-level referential integrity for `target_id`. Tradeoff: schema cleanliness vs. one event table over six. Mitigated by service-level inserts that always target a known entity. See §1.8.
- **Reference data writable by service-role only** — no application-level write path on `addresses` / `buildings` / `dwellings` / `companies`. Means the import pipeline (or an admin RPC) is the only mutator. Cleaner; also a single chokepoint for data-quality checks.
- **Trigram indexes added preemptively** for autocomplete search. Cost is some write amplification on import; benefit is that autocomplete works from day one.
- **Aggregate views are not materialised.** They scan the partial recency index. Cheap at small scale; will need to materialise (or maintain via trigger) once review volume warrants it.
- **One pending revision per review** is enforced by a partial unique index. Simple, but means a user cannot stack edits.
- **Freeze bypass via GUC** (`rml.apply_revision`) is a privileged backdoor. Narrow (one transaction, one function), but it is still a backdoor. The alternative was a wholly separate "live published" table that gets swapped — more complex; rejected for v1.
- **`replies_insert_disabled` placeholder** disables `company_replies` writes entirely at the policy level until the representative mechanism is approved. Table shape stays stable; no contract churn later.
- **`display_name` non-unique** — see §1.5. Collisions are possible but operationally acceptable; the pseudonymity guarantee is stronger this way.
- **Snapshot-based public view** — `public_tenancy_reviews` does not JOIN profiles. Pro: decoupling, survives account deletion. Con: a display-name change between approval cycles does not retroactively update the public view (only refreshes on revision-apply). v1 accepts this — pseudonyms aren't expected to change frequently and the snapshot reflects "what was visible when this was published / last edited".
- **Verification badge included in v1 public view** — the field is exposed as a simple state (§1.3). The UI is free to ignore it if product decides to suppress it; the schema is forward-compatible either way.
- **90-day retention default with no sweeper yet** — see §1.4 and §9 (4). Documents will accumulate past 90 days until the sweeper exists. Operational risk is bounded by the small expected v1 user base.
- **Column-level GRANT posture is "deny by default"** — every user-owned table has `REVOKE UPDATE … FROM authenticated` followed by a column-scoped GRANT. The RLS policy gates *which row*; the column GRANT gates *which column*. Both must allow. Tradeoff: every new user-mutable column must be added explicitly to the GRANT (or stays unmutable). This is the intended posture for an evidence-/identity-bearing schema.

---

## 11. Legally sensitive considerations

The schema deliberately makes the legally-sensitive surfaces narrow:

- **No public profile of private individual landlords.** `companies` has a NOT NULL `cvr_number`; there is no `landlords` table at all. Reviews of private landlords attach to `address_id` only.
- **No public exposure of reporter identity.** `reports.reporter_id` is private (RLS), and the GDPR-erasure path nulls it (§1.7).
- **No public exposure of unit-level address detail.** Floor, door, geo, and dwelling identifiers are withheld from public views (§1.1) so a public review of an address cannot isolate a single household.
- **Verification documents are never reachable from any `public_*` view.** Storage is in a private bucket; signed URLs are minted only in the moderation context (and that minting is itself a `moderation_events` insert, `event_type='evidence_accessed'`). The public verification signal exposes only a state, never document metadata (§1.3).
- **Moderation log is private.** `moderation_events` has no view, no anon access, and is append-only enforced at two layers (RLS + trigger). Even the reviewed party cannot read the moderation history.
- **Author identity ↔ review link is private.** Public views expose `author_display_name` (from the denormalised snapshot) and `verification_status` only. The reviewer-to-real-identity link only exists on `profiles` (private) and `tenancy_reviews.author_id` (private; nullable post-deletion).
- **Right-of-reply for private landlords** is structurally absent (`company_id` is the only FK on `company_replies`, and it is `NOT NULL`). Reply writes are disabled in v1 (§1.2).
- **Defamation risk on free text** is mitigated upstream by pre-publication moderation (`is_high_risk` + the moderation queue), not by the schema. The schema captures the flag and the review lifecycle; the policy in `MODERATION_POLICY.md` is what rejects unsafe content.
- **Retention pause for legal hold** is supported by `verification_documents.legal_hold` (§1.4). The sweeper, once implemented, must respect it.

---

## 12. What this proposal does NOT include

- Buckets themselves (created via Supabase storage; this migration only sketches the policies).
- Concrete rate-limiter keys / windows (`docs/SECURITY_RULES.md` §6 is implemented in application code on Upstash).
- An `analytics_events` table or any product-analytics scaffolding (no decision yet).
- The DAR/BBR/CVR ingestion job's bookkeeping tables (`ingestion_runs`, `dar_diffs`, etc.) — those belong to a separate migration when that pipeline is built.
- Materialised views for aggregates — added if and when needed.
- A `landlords` / `private_landlords` table — deliberately omitted (`PRODUCT_DECISIONS.md` §10).
- A `company_representatives` table — deliberately omitted until the reply mechanism is approved (§1.2).
- The retention sweeper job (§1.4 / §9 item 4) — schema is sweeper-ready, the job is not implemented.
- The account-deletion RPC (§7) — strategy documented, RPC not yet written.
- A first-admin bootstrap RPC (§1.10).

---

## 13. Status

- **Branch:** `feature/schema-v1-proposal`.
- **Files added:** `supabase/migrations/20260524000000_schema_v1_proposal.sql`, `docs/SCHEMA_REVIEW.md`.
- **Applied to any environment:** No.
- **Commits:** None yet (proposal stage).
- **Resolved v1 decisions:** 11 (§1.1 – §1.11). All reflected in the SQL.
- **Resolved review findings:** 10 (4 critical + 6 important — see §1.12).
- **Still-open questions:** 8 (§9). None block applying the migration.
- **Readiness:** safe for local apply / testing.
