# Data Model

Conceptual data model for the **RML** platform. This is a design document, not a
final schema — field lists are indicative. The binding rules are the **public vs
private separation**, the **moderation and verification status fields**, and the
**audit fields**. Update this document in the same change as any schema migration.

---

## 1. Core concept: a review is a tenancy experience

The central entity is **`tenancy_reviews`**. A review represents **one person's
experience of renting one dwelling, during one tenancy period, from one landlord
or company**. It is not a generic comment on a building.

Consequences:

- A review is always anchored to an **address** (and, where known, a specific
  **dwelling/unit**).
- A review records a **tenancy period** (start and, if ended, end date).
- A review records **which landlord/company** the experience was with, because
  the managing party of an address can change over time.
- Aggregate ratings for an address or company are derived from approved reviews.

---

## 2. Entities

### 2.1 `profiles` (users)

Account and reviewer identity.

- `id` (= Supabase Auth user id; one-to-one with `auth.users.id`)
- `display_name` — pseudonymous public handle (see §5)
- `locale` — preferred UI language (`da` / `en`)
- `role` — `user` | `moderator` | `admin`. **Source of truth for authorisation.**
  Writable only via an admin path (RPC or service-role action that re-checks
  the caller is an admin). Not self-assignable. See
  `docs/SECURITY_RULES.md` §12.
- **Private:** real name / contact data, if collected, kept minimal and separate
  from the public profile.
- Audit: `created_at`, `updated_at`.

> A `profiles` row is **provisioned automatically** for every `auth.users` row
> via a database trigger (or equivalent server-side mechanism). Any privileged
> or write action that depends on a profile **fails closed** when the row is
> missing. See `docs/SECURITY_RULES.md` §13.

### 2.2 `buildings`

A physical building. Sourced from / reconciled with BBR over time.

- `id`
- `bbr_building_id` — external reference (nullable until imported)
- address linkage, build year, building type — reference metadata
- Audit: `created_at`, `updated_at`

### 2.3 `addresses`

A Danish address. Sourced from / reconciled with DAR (Datafordeleren).

- `id`
- `dar_address_id` — external reference (nullable until imported)
- `street`, `house_number`, `floor`, `door`, `postal_code`, `city`
- `building_id` — FK to `buildings` (nullable)
- geo coordinates (optional)
- Audit: `created_at`, `updated_at`

### 2.4 `dwellings` (units)

A specific dwelling/unit at an address. Sourced from / reconciled with BBR.

- `id`
- `address_id` — FK
- `bbr_dwelling_id` — external reference (nullable)
- `area_m2`, `rooms` — reference metadata
- Audit: `created_at`, `updated_at`

> Addresses, buildings, and dwellings are **reference data**. They are kept
> distinct from user-generated content and will eventually be populated by the
> import pipeline (see `docs/ARCHITECTURE.md` §7).

### 2.5 `companies`

A landlord company or rental/administration business. Sourced from CVR.

- `id`
- `cvr_number` — external reference (unique where present)
- `name`, `company_type`
- `status` — e.g. active / dissolved (from CVR)
- Audit: `created_at`, `updated_at`

> Reviews of **private individual landlords** (no CVR) are higher-risk. The data
> model must avoid creating a public, searchable dossier of a private person.
> See §6.

### 2.6 `tenancy_reviews`

The central entity. A single tenancy experience.

**Linkage**
- `id`
- `author_id` — FK to `profiles`
- `address_id` — FK to `addresses`
- `dwelling_id` — FK to `dwellings` (nullable)
- `company_id` — FK to `companies` (nullable; null when a private landlord)

**Public structured fields** (shown on public pages once approved)
- `overall_rating` — stars
- sub-ratings: `communication_rating`, `contract_fairness_rating`,
  `maintenance_rating`, `location_rating`
- `monthly_rent` — amount
- `deposit_amount` — amount
- `deposit_returned` — enum: `full` | `partial` | `none` | `not_applicable` | `pending`
- `mould` — enum: `none` | `minor` | `significant`
- `issue_categories` — set of structured tags (e.g. heating, noise, pests, damp,
  unresponsive_landlord)
- `tenancy_start`, `tenancy_end` (end nullable if ongoing)
- `general_text` — **optional** free text (see `docs/PRODUCT_DECISIONS.md`)

**Status fields** (see §3, §4)
- `moderation_status`
- `verification_status`
- `is_high_risk` — flag set when free text contains high-risk content (see §3)

**Audit**
- `created_at`, `updated_at`, `submitted_at`, `published_at` (nullable)

### 2.7 `review_photos`

Photos attached to a review. Become visible on public pages once **both** the
review and the photo itself are `approved`. Visibility is mediated by
short-lived signed URLs minted server-side; the underlying storage bucket is
**private**. See `docs/SECURITY_RULES.md` §3.

- `id`
- `review_id` — FK
- `storage_path` — user-scoped path in the **private `review-photos` bucket**
  (`<auth.uid()>/reviews/<review_id>/<file>`).
- `moderation_status` — a photo can be rejected independently of the review.
- Audit: `created_at`.

### 2.8 `verification_documents`

Evidence that the reviewer was a real tenant (lease, bill, deposit receipt).
**Private. Never public. Never linked from public pages.** Stored in a separate
private bucket from review photos; no public-path signed URLs are ever issued.

- `id`
- `review_id` — FK
- `uploader_id` — FK to `profiles`
- `document_type` — enum: `lease` | `utility_bill` | `deposit_receipt` | `other`
- `storage_path` — user-scoped path in the private `verification-documents`
  bucket (`<auth.uid()>/verification/<review_id>/<file>`).
- `review_status` — moderator's assessment of the evidence.
- `retention_expires_at` — short retention window (see
  `docs/SECURITY_RULES.md` §8).
- Audit: `created_at`.

### 2.9 `moderation_events`

Append-only log of moderation actions. Required for every moderation decision.

- `id`
- `review_id` — FK (or other target reference)
- `actor_id` — FK to `profiles` (the moderator/admin)
- `event_type` — e.g. `submitted` | `approved` | `rejected` | `removed` |
  `verification_reviewed` | `reply_approved` | `report_resolved` |
  `evidence_accessed` | `role_changed` | `review_resubmitted`
- `reason` — structured reason / note
- `previous_status`, `new_status`
- Audit: `created_at`

This table is **append-only** — events are never edited or deleted. Append-only
behaviour is enforced both by the absence of `UPDATE`/`DELETE` RLS policies
and by a defensive trigger. See `docs/SECURITY_RULES.md` §1 and
`docs/MODERATION_POLICY.md` §8.

### 2.10 `reports`

User-submitted reports against a review (or reply).

- `id`
- `reporter_id` — FK to `profiles`
- `review_id` — FK (or reply reference)
- `reason` — structured category (e.g. false, doxxing, harassment, spam, off-topic)
- `details` — optional short text
- `status` — `open` | `under_review` | `resolved` | `dismissed`
- Audit: `created_at`, `resolved_at` (nullable)

### 2.11 `company_replies`

Right-of-reply: a response from a **reviewed CVR-identified company** to a
review. This mechanism is **only** for companies — there is no equivalent for
private individual landlords in the initial product (see
`docs/PRODUCT_DECISIONS.md` §9).

- `id`
- `review_id` — FK
- `company_id` — FK (required; not nullable)
- `author_id` — FK to `profiles` (the verified company representative)
- `body` — reply text
- `moderation_status` — replies are moderated too (see
  `docs/MODERATION_POLICY.md`)
- Audit: `created_at`, `updated_at`, `published_at` (nullable)

---

## 3. Moderation status

`moderation_status` (on reviews, photos, and replies) is an enum:

`pending` → `approved` | `rejected` | `removed`

- New reviews start at `pending`. They are **not publicly visible** until `approved`.
- `rejected` — failed pre-publication moderation; never published.
- `removed` — was published, later taken down (e.g. after a report or takedown).
- Only `approved` content appears on public pages and counts toward aggregates.
- `is_high_risk` is set when free text contains content needing closer review
  (criminal accusations, naming individuals, emotional allegations). High-risk
  reviews are not auto-published; see `docs/MODERATION_POLICY.md`.

### 3.1 Review freezing on publication

Once a review is `approved` (publicly visible), the user **may not silently
edit it**. The published version is frozen.

- Any material edit by the author to a published review creates a new
  `pending` revision. The previous version remains the public version until
  the new revision is moderated and `approved`.
- "Material edit" means any change to a public-safe field that a reader could
  notice: ratings, structured factual fields (rent, deposit, deposit return,
  mould, issue categories, tenancy dates), the free-text body, or attached
  photos. Purely private fields (e.g. internal notes) do not trigger a new
  cycle.
- A new moderation cycle writes a `review_resubmitted` event into
  `moderation_events` and then an `approved`/`rejected` event on resolution.
- Revision history is retained where practical (a `tenancy_review_revisions`
  table, or equivalent), so moderators can compare versions and audit history
  exists. The retention duration follows the general retention decision (open
  question — see `docs/PRODUCT_DECISIONS.md`).
- Photos that change (new photo added, existing photo replaced) each go
  through their own `pending → approved` cycle independently of the review.

---

## 4. Verification status

`verification_status` (on reviews) is an enum:

`unverified` | `pending_verification` | `verified` | `verification_failed`

- A review can be `approved` for publication while still `unverified` — moderation
  and verification are **separate** concerns.
- `verified` means a moderator confirmed, via `verification_documents`, that the
  reviewer was a genuine tenant of that address during that period.
- Verification status may be shown publicly as a trust signal; the underlying
  documents are never shown.

---

## 5. Public vs private fields

A binding separation. See `docs/SECURITY_RULES.md` §9.

**Public** (visible on public pages when the review is approved)
- Structured ratings and structured factual fields (rent, deposit, deposit return,
  mould, issue categories, tenancy dates)
- Moderated optional free text
- Moderated photos (served via short-lived signed URLs minted server-side)
- The reviewer's **pseudonymous display name** only
- Verification status as a trust badge
- Approved company replies

**Private** (never on public pages)
- Real identity of the reviewer and the link between a person and their reviews
- Verification documents and their contents
- Contact details of any party
- Moderation notes, reasons, and the moderation event log
- Reports and reporter identity
- Any private-landlord data beyond what the product deliberately and lawfully shows

Public and private data live in **separate tables / buckets** with separate
policies. Public read paths must be structurally unable to return private fields.

### 5.1 Public-read access pattern (binding)

The `anon` role does **not** receive broad `SELECT` on base tables that mix
public and private columns (notably `tenancy_reviews`, `review_photos`,
`company_replies`). Public reads go through:

- a `public_*` view that selects only public-safe columns and filters to
  publishable state (`moderation_status = 'approved'`), created in the **same
  migration** as the base table; or
- a `SECURITY DEFINER` RPC function with an explicit column whitelist for
  queries a view cannot express.

Repositories never `SELECT *` on a base table for a public path; the column
whitelist is also enforced at the repository layer as defence-in-depth. See
`docs/SECURITY_RULES.md` §9.

---

## 6. Avoiding personal-data exposure for private landlords

- Reviews of **companies** (CVR-identified) are the primary path. Companies
  have public profile pages.
- **Private individual landlords do not have standalone public profile pages**
  in the initial product (see `docs/PRODUCT_DECISIONS.md` §10). Their reviews
  attach to the **address** and the **tenancy experience**. The data model
  must not concentrate identifying data of a private landlord into a public,
  searchable entity.
- Do not store or display a private landlord's home address, contact details,
  or other identifying data beyond what is strictly necessary and lawful.
- Private-landlord reviews are treated as higher-risk in moderation.
- **Right-of-reply for private landlords is deferred** (see
  `docs/PRODUCT_DECISIONS.md` §9). `company_replies` is for CVR-identified
  companies only; no equivalent mechanism is built for private landlords until
  an explicit safe design is approved.

---

## 7. Audit timestamps

Every table carries audit fields. At minimum `created_at`; `updated_at` wherever
rows are mutable. Reviews additionally carry `submitted_at` and `published_at`.
`moderation_events` is append-only and immutable. Audit fields are written by the
server/database, never trusted from client input.
