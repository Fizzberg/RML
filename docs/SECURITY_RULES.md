# Security Rules

Binding security rules for the **RML** web platform. Every feature must comply.
On conflict with convenience, security wins. These rules are mandatory for all
Claude Code work and for human contributors.

RML stores **sensitive data**: tenancy experiences, rent and deposit figures,
photos of homes, and verification documents (leases, bills). It also publishes
**reviews about identifiable parties** (companies and, potentially, private
landlords). Both facts raise the required level of care.

---

## 1. Row Level Security (RLS)

- **Every table has RLS enabled.** No exceptions. RLS is created in the **same
  migration** as the table — never as a later add-on.
- **Every table has explicit policies.** A table with RLS on and no policy is
  effectively closed; that is acceptable as a deliberate default, but the intended
  policies must still be defined.
- Policies check identity via `auth.uid()`. Ownership is derived from a column
  that the user cannot forge.
- **`USING (true)` / `WITH CHECK (true)` is forbidden** unless the data is
  deliberately public **and** the reason is documented in a comment on the policy
  and noted in `docs/DATA_MODEL.md`. Even then, prefer a dedicated `public_*`
  view (see §9) over a permissive policy on the base table.
- Never derive ownership from a request body value or a client-supplied id —
  only from `auth.uid()`.
- Public-read and owner-write are **separate** concerns. A reader being able to
  see a published review must never imply the reader can write or edit it.
- **Base tables that mix public and private fields must not be directly readable
  by the `anon` role.** Public access is mediated by the public-read pattern in
  §9.
- **Moderator/admin permissions are enforced in RLS**, not only in application
  code. Role is read from `profiles.role` (see §12).

### Pattern: owner-managed table

```sql
ALTER TABLE <table> ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Owner can read own rows"
ON <table> FOR SELECT
USING (user_id = auth.uid());

CREATE POLICY "Owner can write own rows"
ON <table> FOR INSERT
WITH CHECK (user_id = auth.uid());
```

### Pattern: published content with mixed columns (e.g. reviews)

For `tenancy_reviews` and any other table that contains both public-safe and
private columns, the `anon` role must **not** receive `SELECT` on the base
table. Author and moderator policies live on the base table; public reads go
through a `public_*` view (see §9).

```sql
-- Authors can always see their own rows in any status.
CREATE POLICY "Authors can read their own reviews in any status"
ON tenancy_reviews FOR SELECT
USING (author_id = auth.uid());

-- Moderators and admins can read all rows.
CREATE POLICY "Moderators can read all reviews"
ON tenancy_reviews FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('moderator', 'admin')
  )
);

-- The anon role is NOT granted SELECT on tenancy_reviews. Public reads go
-- through public_reviews (see §9), which is created in the same migration.
```

A pending, rejected, or removed review must **never** be readable by the public
through any path.

### Append-only tables

Tables that the data model marks append-only (currently `moderation_events`, see
`docs/MODERATION_POLICY.md` §8) must be enforced as append-only at the database:

- **No `UPDATE` policy and no `DELETE` policy is created**, for any role —
  including `moderator` and `admin`. The absence of a policy denies the
  operation under RLS.
- A trigger that raises on `UPDATE` and `DELETE` is added defensively, so that
  even a future privileged session cannot mutate the log without a reviewed
  migration that explicitly removes the trigger.
- Service-role code does not `UPDATE` or `DELETE` append-only rows; the
  append-only guarantee is not bypassed by privileged contexts.
- Every moderation action creates a **new row** in `moderation_events`. Status
  corrections are recorded as new events that supersede earlier ones, never as
  edits.

---

## 2. Service role & privileged access

- The Supabase **service-role key is never** in client/browser code, never in the
  Next.js client bundle, never in a public environment variable.
- Service-role access is used only in trusted server contexts (server actions,
  route handlers, background jobs), and only with the **minimum scope** needed.
- Prefer acting in the **user's context** (anon key + user session + RLS) wherever
  possible. Reach for service-role only when a task genuinely cannot be done under RLS.
- Admin/moderation actions performed with elevated rights must still check the
  caller's role server-side before doing anything.

---

## 3. Storage

- **All Supabase Storage buckets are private. No public buckets.** This is a
  binding decision: the product does not use Supabase's `public` bucket flag.
  Applies to review photos, verification documents, and any future bucket.
- **Two separate buckets** for user uploads, with separate policies:
  - `review-photos` — private; review photos attached to a review.
  - `verification-documents` — private; lease, bill, deposit receipt, and other
    verification evidence. **Never** shown publicly and **never** linked from a
    public page. See §8.
- **Upload paths are user-scoped.** The first path segment is the owner's user id:
  - Correct: `<auth.uid()>/reviews/<review_id>/photo_1.jpg` in `review-photos`.
  - Correct: `<auth.uid()>/verification/<review_id>/lease.pdf` in
    `verification-documents`.
  - Wrong: `photo.jpg`, `uploads/random.png`, any path without an owner segment.
- Storage policies must prevent any user from reading or writing another user's
  objects. Moderator/admin reads (where allowed) follow the role rule in §12.
- **Public pages render review photos only through short-lived signed URLs**
  minted server-side at request time, for review photos whose review is
  `approved` and whose photo is `approved`. The browser never receives a long-
  lived URL, and signed-URL lifetime is short (target: minutes, not hours).
- **Verification documents never receive a signed URL on a public path.** Signed
  URLs for evidence are only ever minted in the moderation context, and that
  minting is itself logged (see `docs/MODERATION_POLICY.md` §8).
- **Allowed image MIME types:** `image/jpeg`, `image/png`, `image/webp`.
- **Allowed document MIME types** (verification only): `application/pdf`,
  `image/jpeg`, `image/png`.
- **Size limits:** images ≤ 10 MB per file; verification documents ≤ 15 MB per file.
  Enforce limits both at the bucket level and in server-side validation.
- MIME type is validated server-side, not trusted from the client-declared type alone.

---

## 4. Logging & errors

- **No sensitive data in logs.** Never log: passwords, tokens, session data,
  service-role keys, full review bodies, contact details, verification documents,
  or full user profiles.
- Acceptable to log: error codes, route/handler names, a hashed or truncated user
  id when needed for debugging, latency, and counts.
- **Users see generic error messages.** Stack traces, database error text, and
  internal detail stay in server logs only.
- Errors from external APIs are caught and translated to generic user-facing
  messages; raw upstream errors are not forwarded to the browser.

---

## 5. Input validation

- **All input is validated server-side.** Client-side validation exists only for
  user experience and is never the security boundary.
- Validate type, length, allowed values, and required fields. Trim strings.
  Reject oversized payloads.
- Use a schema validator (e.g. Zod) at the server-action / route-handler boundary;
  reject anything that does not match before it reaches a repository or the database.
- Never concatenate SQL strings. Use parameterised queries / the Supabase client.
- File uploads: validate MIME type, size, and (for images) basic integrity
  server-side before storing.

---

## 6. Rate limiting

Rate limiting is required, **server-side**, for at least the following actions.
Client-side throttling is UX only and never sufficient.

**Substrate (binding): Upstash Redis** (see `docs/PRODUCT_DECISIONS.md` §11),
typically via `@upstash/ratelimit`. All limits below run on this substrate. No
in-memory or in-process limiters as a security control — they do not survive
serverless cold starts and are bypassable.

| Action | Reason | Indicative limit |
|---|---|---|
| Authentication (login, signup, password reset) | Brute force, account abuse | Per IP + per identifier, short window |
| Review submission | Spam, review bombing | Per user + per address/company, daily |
| Image / document upload | Storage abuse, cost | Per user, daily |
| Address / company search | Scraping, upstream API cost, doxxing-by-enumeration | Per IP + per user, short window |
| Public address/company page reads | Scraping of review content | Per IP, short window — combined with caching |
| Reporting a review | Report abuse / harassment | Per user + per target, daily |
| Signed-URL minting for review photos | Bandwidth / leech abuse | Per IP + per user, short window |

Concrete numbers are tuned during implementation and recorded with the feature.
A global safety cap should also exist for any externally-billed API usage
(Datafordeleren, CVR).

### Anti-scraping and anti-doxxing for public surfaces

- Public search and public pages are rate-limited per IP. Aggressive or
  burst-pattern traffic is throttled or challenged.
- **No unrestricted enumeration APIs are exposed.** Endpoints that could be used
  to walk the entire address, company, or review space (numeric id pagination
  over the full set, "list all reviews", "list all addresses") are not part of
  the product.
- Address and company search returns **bounded result sets** with a hard cap;
  pagination is via opaque cursors, not predictable offsets.
- Search input requires a minimum prefix length so that a single character
  cannot return the global namespace.
- **Future public APIs require explicit maintainer approval.** No new public
  endpoint is added without a documented threat model covering scraping,
  enumeration, and doxxing.
- Search and public-page endpoints log only metadata (status, latency, hashed
  IP-derived key) — never the search term in a way that could reconstruct
  user-identifying queries at scale.

---

## 7. GDPR principles

RML processes personal data of EU residents. The following are designed in from
day one, not retrofitted.

- **Data minimisation.** Collect only what the product needs. Do not store data
  "just in case". Verification documents are collected only to verify a tenancy
  and are not part of the public product.
- **Consent.** Obtain clear consent before collecting personal data, and record
  consent (type, timestamp, version). Separate consents for account data,
  evidence uploads, and any analytics.
- **Right of access / export.** A user can export their data (profile, reviews,
  uploads metadata) in a machine-readable form.
- **Right to erasure.** A user can delete their account and associated personal
  data. Published reviews may be retained in an **anonymised** form where there is
  a lawful basis (see §9), but they must no longer be linkable to the person.
- **Retention.** Define and document a retention period for each data category.
  Verification documents in particular have a **short retention** — see §8.
- **Lawful basis.** Each processing purpose has a documented lawful basis.
  Publishing reviews about businesses relies on legitimate interest balanced
  against the rights of the parties; this balance is documented and revisited.
- **Processor transparency.** Third parties that process personal data (Supabase,
  Vercel, external register APIs) are documented in `docs/API_INTEGRATIONS.md`.

---

## 8. Review evidence: leases, bills, and proof documents

Verification documents (lease agreements, utility bills, deposit receipts, key
handover documents) are the **most sensitive data in the product**. They exist to
verify that a reviewer was a real tenant — not to be published.

- Evidence uploads go to a **separate private bucket** from public review photos.
- Evidence is **never** shown publicly and is **never** linked from public pages.
- Only the uploading user and authorised moderators/admins can access evidence,
  enforced by RLS and storage policies.
- Evidence is used solely to set a review's verification status (see §10), then
  retained only as long as needed to defend that status. Define a short retention
  window and delete or redact afterwards.
- Moderators should, wherever possible, see a **redaction-friendly** view — the
  goal is to confirm name + address + dates, not to read the whole document.
  Prefer asking reviewers to redact unrelated sensitive fields before upload.
- Evidence access by a moderator/admin is itself an auditable event (see
  `docs/MODERATION_POLICY.md`).

---

## 9. Separation of public review data and private verification data

This separation is a core security property of RML.

- **Public review data**: structured ratings, structured factual fields (rent,
  deposit, deposit return, mould yes/no, issue categories), optional moderated
  free text, moderated photos, the pseudonymous reviewer display name.
- **Private verification data**: real identity details, verification documents,
  the link between a real person and a pseudonymous review, contact data, raw
  evidence, moderation notes.
- These live in **separate tables and separate buckets** with separate policies.
  Public-read policies apply only to the public set.
- A query path that serves public pages must be **physically unable** to return
  private fields — enforce this at the schema/policy/repository level, not by
  remembering to omit columns.
- Pseudonymous display identity must not leak the real identity: no email-derived
  handles, no sequential ids that correlate to signup order in a guessable way.

### Public-read pattern (binding)

The `anon` role does **not** receive broad `SELECT` on base tables that mix
public and private fields. Public access to reviews, addresses, companies, and
related data flows through one of:

1. **Public views** named `public_*` (preferred). Each public view selects only
   public-safe columns and filters to publishable state
   (`moderation_status = 'approved'` and, where relevant, photo-level
   `moderation_status = 'approved'`). The view is created in the **same
   migration** as its base table, and the `anon` role is granted `SELECT` only
   on the view, not on the base table.
2. **`SECURITY DEFINER` RPC functions** with an explicit column whitelist, used
   where a view cannot express the query (e.g. aggregates, search-driven
   joins). The function is owned by a least-privilege role; `EXECUTE` is
   granted only to the roles that need it.
3. **Repository-layer column whitelists** as a defence-in-depth layer above (1)
   and (2). The repository never does `SELECT *` on a base table for a public
   path.

A new table that will be read by public pages must include the matching
`public_*` view (or documented RPC) in the same migration. Adding a public read
path without one is a `Definition of Done` failure.

---

## 10. Personal data of landlords and private individuals

- Reviews of **companies** (identified by CVR number) are the primary, lower-risk
  case. Companies have public profile pages (see `docs/ARCHITECTURE.md` §4).
- Reviews naming **private individual landlords** are higher risk: a private
  landlord's name is personal data, and Danish defamation law applies.
- **Private individual landlords do not get standalone public profile pages**
  (see `docs/PRODUCT_DECISIONS.md` §10). Reviews involving them attach to the
  address and tenancy experience. Personal details are minimised; identity is
  not searchable as a stand-alone entity.
- Do not expose a private landlord's contact details, home address (as distinct
  from the rental address), or other identifying data beyond what the product
  deliberately and lawfully shows.
- **Right-of-reply for private individual landlords is deferred** (see
  `docs/PRODUCT_DECISIONS.md` §9). The `company_replies` mechanism is for
  CVR-identified companies only. No private-landlord reply path is built until
  an explicit, safe design is approved.

---

## 11. Mandatory security self-check before completing a feature

Confirm each item explicitly in the PR description for any security-relevant change:

- [ ] Can a user read another user's private data? (Must be: no.)
- [ ] Can a user write or edit another user's data? (Must be: no.)
- [ ] Does every new table have RLS enabled and explicit policies?
- [ ] Is there any `USING (true)` / `WITH CHECK (true)` without a documented reason?
- [ ] Are new storage buckets **private**, with MIME and size limits and
      user-scoped paths? (No public buckets — §3.)
- [ ] If a new table mixes public and private columns, is there a `public_*`
      view (or documented RPC) created in the same migration, with the `anon`
      role granted `SELECT` only on the view? (§9)
- [ ] If new public-page assets exist, are they served via short-lived signed
      URLs minted server-side, not via long-lived public URLs? (§3)
- [ ] If a new append-only table was added, is `UPDATE`/`DELETE` denied by RLS
      *and* by a defensive trigger? (§1)
- [ ] If moderator/admin permissions are required, are they enforced in RLS
      against `profiles.role` (not only in application code)? (§12)
- [ ] If a server action depends on a user having a profile, does it **fail
      closed** when the `profiles` row is missing? (§13)
- [ ] Is all new input validated server-side?
- [ ] Are new high-traffic or abuse-prone actions rate-limited server-side on
      Upstash Redis? (§6)
- [ ] If a new public endpoint was added, has scraping / enumeration / doxxing
      been considered, and are bounded result sets and minimum prefix lengths
      in place where relevant? (§6)
- [ ] Can public pages structurally only return public fields (never
      private/verification data)?
- [ ] Is verification evidence isolated from public review data?
- [ ] Do new data categories have a retention period and an export/deletion path?
- [ ] Are users shown generic errors, with detail only in server logs?
- [ ] Are there no secrets in the diff?

---

## 12. Moderator and admin roles

- **Source of truth for roles is `profiles.role`** (enum: `user`, `moderator`,
  `admin`). Initial product does **not** use Supabase Auth custom claims; if
  custom claims are added later, that is a separate, explicit decision.
- **Role checks happen server-side**, in services and route handlers, before
  any privileged action runs. Hiding admin links in the UI is not a security
  control.
- **RLS policies enforce moderator/admin permissions** at the database level
  too. A server-side bug must not be the only thing standing between a user
  and privileged data. Typical pattern:
  ```sql
  CREATE POLICY "Moderators can read all reviews"
  ON tenancy_reviews FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND p.role IN ('moderator', 'admin')
    )
  );
  ```
- **Role assignment and role changes are admin-only and auditable.** Roles are
  not self-granted by a client. Granting or revoking a role writes an audit
  record (a `moderation_events` entry of type `role_changed`, or an equivalent
  audit table — defined in the migration that introduces the change).
- A user must never be able to write to `profiles.role` for themselves or
  anyone else. The `role` column is updatable only via an admin path (RPC or
  service-role server action that re-checks the caller is an admin).
- Moderator access to private data (verification documents, reporter identity,
  real reviewer identity) is itself logged — see
  `docs/MODERATION_POLICY.md` §8.

---

## 13. Profile provisioning

- A `profiles` row is created **automatically** for every `auth.users` row,
  via a database trigger (or equivalent server-side provisioning that runs
  before any user-initiated action can hit). The trigger is created in the
  same migration that defines `profiles`.
- The `profiles.id` value equals the `auth.users.id` (one-to-one).
- **Fail closed when a profile is missing.** Any privileged or write action
  that depends on the caller's profile (role lookup, ownership, locale, etc.)
  must reject the request with a generic error if `profiles` has no row for
  `auth.uid()`. Public-read paths that do not reference profile data may
  continue to work.
- The trigger writes only the minimum needed (id, default `role = 'user'`,
  default `locale`). It does not copy sensitive auth fields.
- Deletion of a user (GDPR erasure) tears down the `profiles` row and any
  PII-linked rows; published reviews may be retained in anonymised form per
  §7. Audit-log rows in `moderation_events` are not deleted (append-only,
  §1) — the actor reference is anonymised instead.
