# Architecture

Architecture and structure for the **RML** web platform. This document is the
source of truth for where code lives and how layers interact. Update it in the
same change whenever the architecture changes.

---

## 1. Stack

| Area | Choice | Notes |
|---|---|---|
| Framework | Next.js (App Router) | Server-rendered pages — important for SEO of address/company pages |
| Language | TypeScript (strict) | |
| Database | PostgreSQL via Supabase | Relational data; RLS for authorisation |
| Auth | Supabase Auth | Email-based; providers TBD |
| Storage | Supabase Storage | **All buckets private.** Two separate buckets: `review-photos` and `verification-documents`. Public pages access photos via short-lived signed URLs. See `docs/SECURITY_RULES.md` §3. |
| Styling | Tailwind CSS | |
| Components | shadcn/ui | Component primitives |
| Package manager | pnpm | Binding; see `CLAUDE.md` §2 and `docs/PRODUCT_DECISIONS.md` §11 |
| i18n | next-intl | Binding; all user-facing strings route through it (Danish + English) |
| Rate limiting | Upstash Redis | Server-side substrate for limits required by `docs/SECURITY_RULES.md` §6 |
| Hosting | Vercel | Added later |

Rationale highlights: server rendering matters because address and company pages
must rank in search engines; Supabase consolidates database, auth, and storage,
which keeps an early-stage platform from spreading across many vendors.

---

## 2. High-level structure

RML is one Next.js application with three broad surfaces:

1. **Public surface** — landing page, search, address pages, company pages,
   individual review display. Server-rendered, SEO-critical, readable without login.
2. **Authenticated surface** — account, submitting and managing reviews, uploading
   photos and verification documents, reporting reviews.
3. **Admin / moderation surface** — review moderation queue, report handling,
   verification review, company-reply handling, moderation event log. First-class,
   access-restricted area (see §6).

### Directory layout

All source lives under `src/`. The scaffold establishes the binding layout:

```
src/
  app/                         # Next.js App Router (routes, layouts, pages)
    [locale]/                  # Locale-prefixed routes (next-intl, da/en)
      (auth)/                  # Login / signup / account (route group)
      (admin)/                 # Moderation & admin area (role-gated)
      address/[id]/            # Address page (SEO-critical)
      company/[cvr]/           # Company page (SEO-critical)
    api/                       # Route handlers (no locale prefix)
    globals.css                # Tailwind base + design tokens
  components/
    ui/                        # shadcn-style primitives (Button, etc.)
    layout/                    # Shared shells (header, footer, main)
  features/                    # Feature-scoped UI + feature-local types
    auth/ reviews/ addresses/ companies/
    moderation/ search/ uploads/ verification/
  i18n/                        # next-intl routing + request config
  lib/                         # Pure utilities — no Supabase, no env coupling
    utils.ts                   # `cn()` and other tiny helpers
    env.ts                     # Validated env (@t3-oss/env-nextjs + Zod)
  server/                      # Server-only modules (`import 'server-only'`)
    auth/                      # Session and role helpers
    db/                        # Supabase client factories (server + browser)
    repositories/              # The only layer that talks to Supabase
    services/                  # Business logic and rules
    integrations/              # External APIs (DAR / BBR / CVR) — typed DTOs
    rate-limit/                # Upstash Redis limiter factory
  middleware.ts                # next-intl locale routing (future: auth refresh)
messages/                      # da.json / en.json — translation files
docs/                          # Governance and design docs
supabase/
  migrations/                  # SQL migrations — source of truth for schema (added later)
```

The **layer separation in §3 is binding**. Folder names are stable — do not
flatten `server/` into `lib/`, and do not move repositories/services back into
`lib/` (an earlier draft of this doc placed them there; the scaffold supersedes
that). `lib/` is for pure utilities only. Anything that imports Supabase,
Upstash, or env-derived secrets belongs in `server/`.

---

## 3. Layering & separation of concerns

Strict top-to-bottom dependency direction. Lower layers never import upper layers.

**UI components**
- Render markup and handle presentational state.
- **Never query Supabase directly.** Never call external APIs directly.
- Receive data as props or via server components that called a repository/service.

**Server actions / route handlers**
- Entry points for mutations and server-side reads.
- Authenticate, validate input (server-side), call services/repositories, return results.
- Orchestrate only — no large blocks of business logic, no multi-step raw data access.

**Services**
- Business logic and rules (e.g. "a review may only be submitted once per tenancy
  period per user", moderation state transitions, verification logic).
- Orchestrate validation and call repositories and integrations.
- No UI concerns.

**Repositories**
- The only layer that talks to Supabase (database and storage).
- Encapsulate queries and enforce that public read paths return public fields only.
- Public-page reads go through `public_*` views or `SECURITY DEFINER` RPC
  functions; repositories never `SELECT *` on a base table for a public path.
  See `docs/SECURITY_RULES.md` §9.
- No business rules.

**Integrations**
- Wrap external APIs (DAR/Datafordeleren, BBR, CVR). Validate every response
  against an explicit schema before use.
- **Expose typed DTOs to services.** Services and repositories never see raw
  upstream response shapes; the integration layer is the only place that
  knows the wire format. If an upstream provider changes its response, only
  the integration layer (and its DTO mapping) changes.
- Keep API keys server-side. See `docs/API_INTEGRATIONS.md`.

**Database & storage**
- PostgreSQL schema with RLS; Supabase Storage with private buckets only.
- Authorisation is enforced here too (RLS), not only in application code.
- Public reads are mediated by `public_*` views or RPCs (see
  `docs/SECURITY_RULES.md` §9). Append-only tables have no `UPDATE`/`DELETE`
  policies and have defensive triggers (see `docs/SECURITY_RULES.md` §1).

### Hard rules

- **No direct Supabase queries inside UI components.** Data access is a
  repository concern.
- No business logic in presentational components.
- No external API calls from the browser; integrations run server-side.
- **Services never consume raw upstream API responses.** Integrations expose
  validated typed DTOs; services depend on the DTOs only.
- Public-facing query paths must be structurally unable to return private or
  verification data (see `docs/SECURITY_RULES.md` §9).
- Public assets (review photos) are served via short-lived signed URLs minted
  server-side, never via long-lived public URLs (see
  `docs/SECURITY_RULES.md` §3).
- **The frontend architecture, component system, and visual decisions must
  comply with [`DESIGN_PRINCIPLES.md`](DESIGN_PRINCIPLES.md)** — UX philosophy,
  information density, moderation visibility, accessibility baseline (WCAG 2.2
  AA), and the anti-pattern list. Component primitives in
  `src/components/ui/`, layout shells in `src/components/layout/`, and
  feature UI in `src/features/<domain>/` are all in scope. A future
  `docs/DESIGN.md` (visual tokens and component API) implements
  `DESIGN_PRINCIPLES.md` and must not contradict it.

---

## 4. Route structure

Indicative routes. Danish-friendly slugs may be used; final naming decided during
implementation. SEO-critical pages are marked.

| Route | Purpose | Access | SEO |
|---|---|---|---|
| `/` | Landing page with primary search | Public (rate-limited) | Yes |
| `/search` | Search results (address / company) | Public (rate-limited; bounded result sets; min prefix; opaque cursor) | Yes |
| `/address/[id]` | Address page: aggregate ratings + approved reviews | Public (rate-limited) | **Critical** |
| `/company/[cvr]` | Company page: aggregate across their addresses | Public (rate-limited) | **Critical** |
| `/review/new` | Structured review submission form | Authenticated | No |
| `/review/[id]` | Single review detail | Public (only if approved; rejected / removed behaviour is an open question — see `docs/PRODUCT_DECISIONS.md`) | Yes |
| `/account` | Profile, the user's own reviews, data export/deletion | Authenticated | No |
| `/login`, `/signup` | Authentication | Public (rate-limited) | No |
| `/admin` | Moderation dashboard (queue, reports, verification) | Admin/Moderator | No |
| `/legal/*` | Privacy policy, terms, imprint, takedown info | Public | Yes |

There is **no** public profile page for private individual landlords (see
`docs/PRODUCT_DECISIONS.md` §10). Company pages exist only for CVR-identified
companies.

No unrestricted enumeration/listing API is exposed (see
`docs/SECURITY_RULES.md` §6). New public endpoints require explicit maintainer
approval with a documented anti-scraping / anti-doxxing analysis.

Search is a **core product surface**, not a secondary feature — see
`docs/PRODUCT_DECISIONS.md`. The address page is the canonical unit a review
attaches to.

---

## 5. Public SEO pages

- Address and company pages must be **server-rendered** with correct metadata
  (title, description, structured data) so they are discoverable when people search
  for a specific address or rental company.
- Only **approved** reviews and **public** fields appear on these pages.
- Pending, rejected, removed, or private data must never render on a public page,
  even transiently.
- Aggregate figures (average rating, counts) are computed from approved reviews only.

---

## 6. Admin / moderation area

The moderation area is **first-class architecture**, designed alongside the public
product — not bolted on later.

- A restricted route group (`app/(admin)/`) gated by role, enforced server-side
  and by RLS, not by hiding links in the UI.
- Surfaces: the pre-publication review queue, reported-review handling,
  verification-document review, company-reply handling, and the moderation event log.
- Every moderation action writes a `moderation_events` record (see `docs/DATA_MODEL.md`).
- Moderator/admin roles are assigned through a controlled path, never self-granted
  by a client.
- Behaviour and rules of this area are defined in `docs/MODERATION_POLICY.md`.

---

## 7. Future import / sync pipeline (DAR, BBR, CVR)

For the MVP, address and company lookups may call external APIs live (see
`docs/API_INTEGRATIONS.md`). The long-term architecture imports reference data
into RML's own PostgreSQL so search is fast, cheap, and fully under RML's control.

Planned pipeline (later phase):

- **Ingestion jobs** that periodically import / refresh data from DAR/Datafordeleren
  (addresses), BBR (building and dwelling metadata), and CVR (companies).
- Imported reference data lives in dedicated tables, kept distinct from
  user-generated content (reviews, photos).
- Search queries RML's local tables; external APIs become a fallback / enrichment
  path rather than the hot path.
- Jobs are idempotent, incremental where possible, and observable (success/failure
  is visible).

This pipeline is **not** part of the initial governance scope and is built only
when explicitly planned. It is recorded here so the schema and search layer are
designed to accommodate it from the start.
