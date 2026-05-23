# RML

Denmark-focused apartment and landlord review platform.

This repository is in the **architecture-shell phase**. There is no business
logic yet — only the technical foundation.

Before doing any work, read [`CLAUDE.md`](./CLAUDE.md) and the documents in
[`docs/`](./docs). They are binding.

## Requirements

- Node.js ≥ 20 (see `.nvmrc`)
- pnpm ≥ 9 (binding package manager — do not mix with `npm` or `yarn`)

If you don't have pnpm:

```bash
npm install -g pnpm
```

## Setup

```bash
pnpm install
cp .env.example .env.local
# Fill in .env.local with your Supabase and Upstash credentials.
pnpm dev
```

The app runs on <http://localhost:3000>.

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

## Project layout

The source lives under `src/`. The top-level shape is:

```
src/
  app/             Next.js App Router routes (locale-prefixed via next-intl)
  components/
    ui/            Reusable presentational primitives (shadcn-style)
    layout/        Shared layout shells (header, footer, main)
  features/        Feature-scoped UI and feature-local types
    auth/ reviews/ addresses/ companies/ moderation/ search/ uploads/ verification/
  i18n/            next-intl routing + request config
  lib/             Pure utilities (no Supabase, no env coupling)
  server/          Server-only code (do not import from client components)
    auth/          Session and role helpers
    db/            Supabase client factories
    repositories/  Data access (the only layer that talks to Supabase)
    services/      Business logic and rules
    integrations/  External APIs (DAR / BBR / CVR)
    rate-limit/    Upstash Redis rate-limiter factories
messages/          Translation files (da.json, en.json)
docs/              Binding governance and design docs
```

The full architectural rules live in [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).
Lower layers never import upper layers. UI never queries Supabase directly.

## Internationalisation

Locales: Danish (`da`, default) and English (`en`). All user-facing strings go
through [next-intl](https://next-intl.dev). Routes are locale-prefixed; the
default locale uses `localePrefix: 'as-needed'`.

To add a string:

1. Add the key + Danish value to `messages/da.json`.
2. Add the same key + English value to `messages/en.json`.
3. Read it with `useTranslations(...)` (client) or `getTranslations(...)` (server).

A change that adds a string in one language but not the other is treated as
incomplete (see [`CLAUDE.md`](./CLAUDE.md) §9).

## Environment

Environment variables are validated at startup in [`src/lib/env.ts`](./src/lib/env.ts)
using `@t3-oss/env-nextjs`. Server-only variables are not exposed to the
browser; only `NEXT_PUBLIC_*` variables are.

Never commit `.env*` files. Only `.env.example` is tracked.

## Git workflow

Commits and pushes are not automated. Open the diff, review, and commit
intentionally. See [`CLAUDE.md`](./CLAUDE.md) §1.5.
