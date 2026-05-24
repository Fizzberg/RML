# RML

Denmark-focused apartment and landlord review platform.

Before doing any work, read [`CLAUDE.md`](./CLAUDE.md) and the documents in
[`docs/`](./docs) — they are binding governance.

---

## Project status

- **Architecture shell + schema v1 proposal** are in place. The Next.js app
  scaffolds the route groups and the server-side layering; the database
  schema for v1 is drafted as a single migration and has been applied
  successfully against a local Supabase stack.
- **No application logic yet.** Pages render placeholders; auth, search,
  review submission, moderation, and uploads are not implemented.
- **No remote Supabase project linked.** Everything runs locally against
  the Supabase CLI's Docker stack. Production deployment is a later step.
- The schema proposal is documented in
  [`docs/SCHEMA_REVIEW.md`](./docs/SCHEMA_REVIEW.md) and the migration file
  lives at `supabase/migrations/20260524000000_schema_v1_proposal.sql`.
- Default branch is `main`. Feature work lives on `feature/<short-name>`
  branches; see [Repository conventions](#repository-conventions).

---

## Tech stack

| Area | Choice |
| --- | --- |
| Framework | Next.js 15 (App Router) |
| Language | TypeScript (strict) |
| Database | PostgreSQL 17 via Supabase |
| Auth | Supabase Auth |
| Storage | Supabase Storage (private buckets only) |
| Styling | Tailwind CSS 3.4 + shadcn-style primitives |
| i18n | next-intl (Danish + English) |
| Rate limiting | Upstash Redis (server-side; not yet wired into routes) |
| Package manager | pnpm (binding — do not mix with `npm` or `yarn`) |
| Local dev DB | Supabase CLI (Docker) |
| Hosting | Vercel (later) |

Full architectural rules: [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).
UX governance: [`docs/DESIGN_PRINCIPLES.md`](./docs/DESIGN_PRINCIPLES.md).

---

## Requirements

- **Node.js ≥ 20** (see `.nvmrc`).
- **pnpm ≥ 9** — binding package manager.
- **Docker** — required by the Supabase CLI to run the local stack
  (Postgres, Studio, Auth, Storage, Inbucket, etc.).
- **Supabase CLI** — used for `start`, `db reset`, `migration new`, and
  related commands.

Install Supabase CLI (macOS):

```bash
brew install supabase/tap/supabase
```

Other platforms: <https://supabase.com/docs/guides/local-development/cli/getting-started>.

Install pnpm if missing:

```bash
npm install -g pnpm
```

---

## Setup

```bash
# 1. Install JS dependencies.
pnpm install

# 2. Create a local environment file from the template.
cp .env.example .env.local
# (leave the Supabase keys blank for now — we fill them in below)

# 3. Start the local Supabase stack (Docker).
#    This brings up Postgres, Studio, Auth, Storage, Inbucket, etc., and
#    applies all migrations in supabase/migrations/ on first boot.
supabase start
```

Do **not** run `supabase init` — the project is already initialised and
[`supabase/config.toml`](./supabase/config.toml) is tracked in git.

After `supabase start` finishes, get the local credentials:

```bash
supabase status
```

Copy the printed `API URL`, `anon key`, and `service_role key` into your
`.env.local`:

```env
NEXT_PUBLIC_APP_URL="http://localhost:3000"
NEXT_PUBLIC_SUPABASE_URL="http://127.0.0.1:54321"
NEXT_PUBLIC_SUPABASE_ANON_KEY="<anon key from supabase status>"
SUPABASE_SERVICE_ROLE_KEY="<service_role key from supabase status>"

# Optional in local dev — leave blank if you don't need rate limiting yet.
UPSTASH_REDIS_REST_URL=""
UPSTASH_REDIS_REST_TOKEN=""
```

Then run the app:

```bash
pnpm dev
```

The Next.js app runs on <http://localhost:3000>.

---

## Local URLs

When `supabase start` is running, the following services are reachable:

| Service | URL | Purpose |
| --- | --- | --- |
| App (Next.js) | <http://localhost:3000> | The product. |
| Supabase Studio | <http://127.0.0.1:54323> | Browse tables, run SQL, inspect policies. |
| Supabase API | <http://127.0.0.1:54321> | What the app talks to. |
| Postgres (direct) | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` | Direct psql / GUI access. |
| Inbucket (email) | <http://127.0.0.1:54324> | Local SMTP catcher — see emails the app would have sent. |

Ports are pinned in [`supabase/config.toml`](./supabase/config.toml) and
are identical on every contributor's machine.

---

## Database workflow

The repo is the source of truth for the schema (per
[`CLAUDE.md`](./CLAUDE.md) §5). Migration files live in
`supabase/migrations/` and follow the naming convention
`YYYYMMDDHHMMSS_description.sql`.

| Task | Command |
| --- | --- |
| Apply all migrations from scratch against the local DB | `supabase db reset` |
| Start the local stack (and apply migrations on first boot) | `supabase start` |
| Stop the local stack | `supabase stop` |
| Show local credentials and URLs | `supabase status` |
| Create a new migration file (UTC timestamp prefix) | `supabase migration new <description>` |

**Current migration.** A single v1 proposal:

```
supabase/migrations/20260524000000_schema_v1_proposal.sql
```

It includes the core tables (`profiles`, `addresses`, `dwellings`,
`buildings`, `companies`, `tenancy_reviews`, `tenancy_review_revisions`,
`review_photos`, `verification_documents`, `moderation_events`, `reports`,
`company_replies`), RLS, public-read views, triggers, and the admin /
revision-apply RPCs. See
[`docs/SCHEMA_REVIEW.md`](./docs/SCHEMA_REVIEW.md) for the design
rationale and the still-open questions.

**Seed data.** The CLI is configured (in `supabase/config.toml`) to look
for `supabase/seed.sql` and apply it after migrations during `db reset`.
The file is present and minimal — local-dev-only fictional data:

- 3 `auth.users` rows (`admin@dev.local`, `renter-aarhus@dev.local`,
  `tenant-cph@dev.local`), each backed by a `profiles` row produced by
  the auth-user trigger; the first is promoted to `role = 'admin'`.
- 3 buildings, 4 fictional Danish-style addresses, 3 dwellings.
- 3 companies with the `(DEV ONLY)` suffix and CVR numbers starting `99…`.
- 4 reviews covering the lifecycle: 2 approved (one company-linked, one
  address-only / private-landlord case), 1 pending, 1 rejected with
  `is_high_risk = true`.
- 8 `moderation_events` rows reflecting each review's lifecycle, plus
  one `role_changed` event for the initial admin promotion.

No real names, no real addresses, no real CVRs, no real reviews. See the
file header for the full do-not-list. Password sign-in via Supabase Auth
is intentionally not enabled by the seed — `auth.identities` is not
populated. Read-side browsing of public views and Studio inspection work
out of the box.

**No destructive operations against any remote DB.** This repo runs only
against the local CLI stack at the moment. Schema changes that are
destructive (drops, renames, type changes) follow the
expand/contract pattern in [`CLAUDE.md`](./CLAUDE.md) §5.2 once a real
remote exists.

---

## Scripts

| Command | Description |
| --- | --- |
| `pnpm dev` | Run the Next.js dev server. |
| `pnpm build` | Production build. |
| `pnpm start` | Run the production build. |
| `pnpm lint` | Lint with ESLint (uses `eslint-config-next`). |
| `pnpm lint:fix` | Lint with autofix. |
| `pnpm typecheck` | Strict TypeScript type-check (no emit). |
| `pnpm format` | Format all files with Prettier. |
| `pnpm format:check` | Verify formatting without writing. |

---

## Project layout

```
src/
  app/             Next.js App Router (locale-prefixed via next-intl)
    [locale]/      Public routes (homepage, address, company)
      (auth)/      Login / signup (route group)
      (admin)/     Moderation area (route group — gated server-side)
    api/           Route handlers (currently only /api/health)
    globals.css    Tailwind base + design tokens
  components/
    ui/            Reusable primitives (shadcn-style — Button so far)
    layout/        Site header, site footer
  features/        Feature-scoped UI + feature-local types
    auth/ reviews/ addresses/ companies/
    moderation/ search/ uploads/ verification/
  i18n/            next-intl routing + request config
  lib/             Pure utilities (no Supabase, no env coupling)
  server/          Server-only code (do not import from client components)
    auth/          Session + role helpers (fail-closed today)
    db/            Supabase client factories (server + browser)
    repositories/  Data access (the only layer that talks to Supabase)
    services/      Business logic and rules
    integrations/  External APIs (DAR / BBR / CVR)
    rate-limit/    Upstash Redis limiter factory
  middleware.ts    next-intl locale routing

messages/          Translation files (da.json, en.json)
supabase/
  config.toml      Local Supabase stack configuration (tracked)
  .gitignore       Scoped ignores for Supabase scratch files
  migrations/      SQL migrations — source of truth for schema
docs/              Binding governance and design docs
```

Layering is binding (`docs/ARCHITECTURE.md` §3): lower layers never import
upper layers; UI never queries Supabase directly; public-page reads go
through `public_*` views, never base tables.

---

## Internationalisation

Locales: Danish (`da`, default) and English (`en`). All user-facing
strings go through [next-intl](https://next-intl.dev). Routes are
locale-prefixed; the default locale uses `localePrefix: 'as-needed'` (so
Danish UI lives on bare paths, English on `/en/...`).

To add a user-facing string:

1. Add the key + Danish value to `messages/da.json`.
2. Add the same key + English value to `messages/en.json`.
3. Read it with `useTranslations(...)` (client) or `getTranslations(...)`
   (server).

A change that adds a string in one language but not the other is treated
as incomplete (see [`CLAUDE.md`](./CLAUDE.md) §9).

---

## Environment

Environment variables are validated at startup in
[`src/lib/env.ts`](./src/lib/env.ts) using `@t3-oss/env-nextjs`.
Server-only variables are not exposed to the browser; only `NEXT_PUBLIC_*`
variables are. See [`.env.example`](./.env.example) for the full list.

Never commit `.env*` files. Only `.env.example` is tracked. To skip
validation in CI lint/typegen steps, set `SKIP_ENV_VALIDATION=true`.

---

## Repository conventions

- **Default branch:** `main`.
- **Feature branches:** `feature/<short-description>`. Open a PR back to
  `main` (or, for solo work, fast-forward locally — both are fine as long
  as history stays linear).
- **Commits are not automated.** No commit, push, amend, rebase, force
  push, or tag without an explicit instruction from a maintainer for that
  specific action ([`CLAUDE.md`](./CLAUDE.md) §1.5).
- **No AI attribution in commit messages or PR descriptions** — no
  `Co-Authored-By: Claude …` lines, no `Generated by …` trailers, no
  tool-provenance markers ([`CLAUDE.md`](./CLAUDE.md) §1.6).
- **Hooks are not bypassed.** `--no-verify` is not used.
- Documentation drift is treated as an incomplete change — update the
  relevant doc in `docs/` in the same change.

---

## Documentation

All governance docs live under [`docs/`](./docs). Read them when you join
the project; they are binding.

| Document | Purpose |
| --- | --- |
| [`CLAUDE.md`](./CLAUDE.md) | Binding working rules for every contributor — workflow, commit policy, stack, layering, security, secrets, i18n, definition of done. |
| [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) | Stack, directory layout, layering, route map, public SEO pages, admin area, future import pipeline. |
| [`docs/DATA_MODEL.md`](./docs/DATA_MODEL.md) | Entities, public vs private fields, moderation/verification status, review-freezing model, audit fields. |
| [`docs/SECURITY_RULES.md`](./docs/SECURITY_RULES.md) | RLS, storage, validation, rate limiting, GDPR, evidence handling, anti-doxxing, role mechanism, profile provisioning. |
| [`docs/MODERATION_POLICY.md`](./docs/MODERATION_POLICY.md) | Pre-publication moderation, high-risk flagging, photos, replies, reports, append-only event log. |
| [`docs/PRODUCT_DECISIONS.md`](./docs/PRODUCT_DECISIONS.md) | Binding product decisions (anonymity, structured form, search-as-core, etc.) and open questions. |
| [`docs/API_INTEGRATIONS.md`](./docs/API_INTEGRATIONS.md) | DAR / BBR / CVR — live-MVP vs imported-cache strategy, key handling, DTO boundary. |
| [`docs/DESIGN_PRINCIPLES.md`](./docs/DESIGN_PRINCIPLES.md) | UX philosophy, information density, moderation visibility, WCAG 2.2 AA baseline, anti-patterns. |
| [`docs/SCHEMA_REVIEW.md`](./docs/SCHEMA_REVIEW.md) | v1 schema proposal — resolved decisions, hardening pass, local-apply verification, still-open questions. |
| [`docs/PRODUCT_NOTES.md`](./docs/PRODUCT_NOTES.md) | Living, collaborative thinking space — exploratory product direction, UX notes, open questions, ideas in flight. Safe place to drop unfinished thoughts; contradictions and reorganisation are expected. Explicitly **not** a spec — anything binding lives in `docs/PRODUCT_DECISIONS.md` and the other governance docs. |

---

## Current limitations / intentionally unfinished

These are tracked deliberately. They are part of "v1 scope" *plus* known
gaps the maintainer accepts at this stage.

- No real authentication flows wired to the routes — `(auth)/login` and
  `(auth)/signup` render placeholders.
- No review submission, search, moderation, or upload UI.
- No address / company import pipeline (DAR / BBR / CVR live calls are
  designed for, but not yet implemented).
- Storage buckets `review-photos` and `verification-documents` are
  documented in the schema and `docs/SECURITY_RULES.md` §3 but **not yet
  created** in the local stack.
- `supabase/seed.sql` exists and is minimal — local-dev fictional rows
  only. Password sign-in is not yet enabled by the seed
  (`auth.identities` is intentionally not populated).
- No retention sweeper for `verification_documents` —
  `retention_expires_at` defaults to 90 days but nothing acts on it yet.
- No first-admin bootstrap RPC — the first `admin` is promoted via a
  manual `UPDATE public.profiles SET role = 'admin' WHERE id = '…'` (see
  [`docs/SCHEMA_REVIEW.md`](./docs/SCHEMA_REVIEW.md) §1.10).
- No application-layer rate limiting yet — the
  `server/rate-limit/index.ts` factory exists and Upstash credentials
  flow through `env.ts`, but no surface uses it.
- The Supabase session-refresh middleware is not yet wired alongside the
  next-intl middleware in `src/middleware.ts`.
- No remote Supabase project linked; everything is local-only.

---

## Next milestones

Indicative — not commitments. See `docs/PRODUCT_DECISIONS.md` for the
binding direction.

- Wire Supabase Auth into the `(auth)/login` and `(auth)/signup` routes;
  add a Supabase session-refresh middleware. (Once login is wired, extend
  the seed to populate `auth.identities` so the seeded users can actually
  sign in.)
- Implement the route-level role guard for `(admin)/` using
  `server/auth/require-role.ts`.
- Create the two private storage buckets and implement the server route
  that mints short-lived signed URLs for approved review photos.
- Build address search via the DAR integration (`server/integrations/`).
- Build the review submission form against the v1 schema.
- Implement the moderation queue UI.
- Implement the retention sweeper for verification documents.
