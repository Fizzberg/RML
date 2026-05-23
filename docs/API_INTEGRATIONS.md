# API Integrations

External data integrations for **RML**. This document defines which external
sources RML uses, how they are accessed, and the rules for handling them. Update
it in the same change whenever an integration is added or changed.

RML relies on Danish public registers for its reference data: addresses, building
and dwelling metadata, and company information. User-generated content (reviews,
photos) is RML's own data and is never sourced externally.

---

## 1. Sources

### 1.1 DAR / Datafordeleren — Danish addresses

- **Purpose:** the authoritative source of Danish addresses. Powers address search
  and autocomplete, which is the entry point to the whole product.
- **Source:** Danmarks Adresseregister (DAR), accessed via the **Datafordeleren**
  platform.
- Addresses are the unit a review attaches to (see `docs/DATA_MODEL.md`).

### 1.2 BBR — building and dwelling metadata

- **Purpose:** physical metadata for buildings and dwellings (build year, area,
  rooms, dwelling/unit breakdown). Enriches address and dwelling records.
- **Source:** Bygnings- og Boligregistret (BBR), via Datafordeleren.

### 1.3 CVR — company lookup

- **Purpose:** identify and look up landlord companies and rental/administration
  businesses by name or CVR number. Companies are a primary review target.
- **Source:** Det Centrale Virksomhedsregister (CVR).

---

## 2. Do not depend on DAWA

- **DAWA (Danmarks Adressers Web API) must not be the architecture's address
  source.** DAWA is being decommissioned — it is scheduled to shut down on
  **1 July 2026**, and its address data stops being updated before that.
- RML uses **DAR via Datafordeleren directly** for addresses. Datafordeleren is
  the platform the Danish public-data infrastructure is consolidating on.
- If any example, tutorial, or library suggests building on DAWA, do not follow it
  for RML's core address integration. A short-lived prototype that touches DAWA is
  not acceptable as a foundation; build on DAR/Datafordeleren from the start.

---

## 3. MVP vs long-term strategy

### 3.1 MVP — live API calls are acceptable

For the initial MVP, RML may call the external register APIs **live** (server-side)
for address search, dwelling metadata, and company lookup. This is acceptable to
get the product working without first building an ingestion pipeline.

Constraints even in the MVP:

- Calls are made **server-side only** (see §4).
- Live search calls are rate limited and cached briefly to control cost and latency
  (see `docs/SECURITY_RULES.md` §6).
- Responses are validated before use (see §5).

### 3.2 Long-term — local import / cache for fast search

The long-term architecture imports register data into RML's own PostgreSQL so
search is fast, cheap, predictable, and not dependent on a third party being up.

- Periodic ingestion jobs import / refresh DAR (addresses), BBR (buildings and
  dwellings), and CVR (companies) into dedicated reference tables.
- Search then queries RML's local tables; the external APIs become a
  fallback / enrichment path rather than the hot path.
- Imported reference data is kept distinct from user-generated content.
- See `docs/ARCHITECTURE.md` §7 for the pipeline outline.

The import pipeline is a **later phase** — built only when explicitly planned. The
schema and search layer are designed now so that moving from live calls to local
data does not require re-architecting.

---

## 4. Keys and secrets

- All credentials for external APIs (Datafordeleren access credentials / API keys,
  CVR access credentials) are **server-side only**.
- They are never in client/browser code, never in the Next.js client bundle, never
  in a public environment variable, never committed to the repo.
- External API calls run from server actions, route handlers, or background jobs —
  never from the browser.
- Credentials live in environment variables / deployment secrets; only
  `.env.example` with placeholder values is committed. See `CLAUDE.md` §7.

---

## 5. Handling external responses

- **Validate every external response** before using it. Do not assume an external
  API returns the expected shape — parse and validate against an explicit schema
  (e.g. Zod) at the integration boundary.
- Handle failure explicitly: timeouts, rate-limit responses, partial data, and
  outages. An external failure must produce a generic, graceful user-facing
  message — never a raw upstream error and never a crash.
- Set sensible timeouts on external calls; do not let a slow register API block a
  user flow indefinitely.
- Treat external data as **untrusted input** for security purposes: validate and
  sanitise it the same way as any other input before storing or displaying it.
- Do not log full external responses if they could contain personal data; log
  status, latency, and error codes only (see `docs/SECURITY_RULES.md` §4).

---

## 5.1 Integration boundary: typed DTOs (binding)

The integration layer is the **only** layer that knows the wire shape of an
external API. The rest of the application consumes **typed DTOs** produced by
the integration layer.

- Each integration module (DAR/Datafordeleren, BBR, CVR) exposes a set of typed
  DTOs that represent the shapes RML cares about — not the raw upstream JSON.
- The integration validates the raw response against a schema, then maps it to
  a DTO. The mapping is the only place that handles upstream quirks (field
  naming, optionality, encoding).
- **Services and repositories never import raw upstream types** and never call
  external APIs directly. They depend on the DTOs.
- An upstream API change is contained to one place: the integration module and
  its schema. The rest of the codebase compiles and runs against the DTOs.
- DTOs are designed for RML's needs (search, dedup, enrichment); they are not
  a 1:1 mirror of the upstream payload.

---

## 6. Data protection note

DAR, BBR, and CVR are official Danish registers. Where data obtained from them
relates to identifiable people (for example, certain company or ownership data),
it is personal data and is subject to the GDPR principles in
`docs/SECURITY_RULES.md` §7. External processors and data sources that handle
personal data are documented as part of RML's processing transparency.
