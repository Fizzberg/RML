# Product Decisions

Binding product decisions for **RML**. Each decision holds until it is explicitly
revisited and this document is updated. When a new block of work changes or adds a
product decision, record it here in the same change.

Format per entry: the decision, then a short rationale.

---

## 1. An authenticated account is required to submit a review

Submitting a review requires a logged-in account.

*Rationale:* accountability and anti-abuse. Requiring an account makes review
bombing and spam harder, enables verification, allows a user to manage and delete
their own reviews, and gives moderation a real subject to act on. It also supports
GDPR rights (export, deletion) which need an identifiable account.

## 2. Public reviewer identity is anonymous / pseudonymous

A reviewer is identified publicly only by a pseudonymous display name. Their real
identity is never shown on public pages.

*Rationale:* tenants must be able to report a bad rental experience without fear
of retaliation from a landlord or company. Pseudonymity lowers that barrier while
the account requirement (Decision 1) preserves accountability behind the scenes.

## 3. Reviews are pre-moderated at launch

Every review is moderated **before** it becomes publicly visible. Nothing is
published automatically at launch.

*Rationale:* legal safety and review quality. RML publishes statements about
identifiable parties; pre-publication moderation reduces defamation exposure,
filters spam and abuse, and sets a quality bar. Post-publication moderation may be
reconsidered later for low-risk content, but only as an explicit future decision.

## 4. The structured form is primary; free text is optional

The review is built from structured inputs (ratings, amounts, enums, issue tags).
Free-text description is optional and secondary.

*Rationale:* structured factual fields are faster to fill, easier to moderate,
comparable across reviews, and far safer legally than free-form accusations. They
also power the fast-submission target (Decision 5). Free text adds colour but is
not required and is the part most likely to need moderation.

## 5. Target UX: find in 10 seconds, submit in 60 seconds

Finding an address or company should take a user at most ~10 seconds. Submitting a
review should take at most ~60 seconds.

*Rationale:* completion rate. The product only has value with enough reviews, and
friction kills volume. This drives concrete design: fast address autocomplete as
the entry point, tappable structured inputs (stars, toggles, sliders, chips)
rather than typing, optional photos, and optional free text.

## 6. Danish and English UI are both planned

The interface supports Danish and English.

*Rationale:* the audience and data are Danish, so Danish is essential; English
broadens reach (including international tenants and students renting in Denmark).
All user-facing strings route through the i18n layer; no hardcoded strings.

## 7. Address and company search is core product, not a secondary feature

Search is treated as a primary surface and is engineered accordingly.

*Rationale:* search is the first thing every user does and the gate to the 10-second
target in Decision 5. It is not a side feature; its speed and accuracy directly
determine whether the product works.

## 8. No live publishing of high-risk allegations without moderation

High-risk content — criminal accusations, allegations against named individuals,
emotionally charged claims — is never auto-published. It is flagged and held for
closer moderation review.

*Rationale:* this is the highest legal-risk content in the product. It must always
pass human review before publication. This complements Decision 3 and is detailed
in `docs/MODERATION_POLICY.md`.

## 9. Right-of-reply is planned for companies; private-landlord reply is deferred

A reviewed **company** (CVR-identified) will be able to submit a reply to a
review, subject to moderation, via the `company_replies` mechanism (see
`docs/DATA_MODEL.md` §2.11 and `docs/MODERATION_POLICY.md` §6).

Right-of-reply for **private individual landlords** is **not** part of the
initial product. There is no safe mechanism yet for authenticating a private
landlord, protecting reviewer pseudonymity during such a flow, or preventing the
reply mechanism from becoming a re-identification channel. It remains an open
design issue (see the list below) and must not be built until an explicit
decision is recorded here.

*Rationale:* fairness and legal posture. Allowing the reviewed party to respond
makes the platform balanced and is a meaningful mitigation when publishing
statements about identifiable parties — but the private-landlord case carries
disproportionate doxxing and harassment risk and is paused deliberately.

## 10. Private individual landlords do not get standalone public profile pages

Reviews involving private individual landlords attach to the **address** and the
**tenancy experience**. There is **no** public, searchable profile page for a
private individual landlord in the initial product. Companies (CVR-identified)
are the only party type with public profile pages.

*Rationale:* a public, searchable profile page of a private individual is the
single highest-risk surface in a review platform — it converts the product into
a doxxing tool and concentrates defamation exposure on a named natural person.
Attaching the experience to an address preserves the useful signal for future
tenants without standing up a dossier on a private person. Revisited only with
an explicit, written decision here.

## 11. Toolchain decisions (binding)

These supplement the stack table in `CLAUDE.md` §2 and are binding for all work.

- **Package manager: pnpm.** Lockfile is `pnpm-lock.yaml`. Do not introduce
  `package-lock.json` or `yarn.lock`. *Rationale:* a single lockfile keeps CI
  reproducible; pnpm's strict node_modules layout catches accidental
  cross-package imports early.
- **i18n library: next-intl.** All user-facing strings go through next-intl. No
  ad-hoc localisation utilities. *Rationale:* next-intl integrates with the App
  Router's server-component model, which matches the SEO-critical address and
  company pages.
- **Rate limiting substrate: Upstash Redis.** All server-side rate limits
  required by `docs/SECURITY_RULES.md` §6 use Upstash Redis (typically via
  `@upstash/ratelimit`). *Rationale:* serverless-friendly, low-latency, no
  long-lived connections, fits the Vercel deployment target. Client-side
  throttling remains UX-only and is never the security boundary.

---

## Open questions (not yet decided — do not implement)

These are explicitly **not** decisions yet. Do not build for them without a
maintainer decision recorded above.

- Whether and how a verification badge is displayed publicly.
- Auth providers beyond email (social login, MitID, etc.).
- **Concrete retention durations** per data category (see
  `docs/SECURITY_RULES.md` §7) — verification documents in particular.
- Whether post-publication moderation is ever allowed for low-risk content.
- **Takedown / notice-and-action SLA** (acknowledgement window, decision window)
  for `docs/MODERATION_POLICY.md` §7.
- **GDPR breach / incident runbook** (who is notified, within what window, what
  is logged) — Art. 33 obligation; see `docs/SECURITY_RULES.md`.
- **Right-of-reply mechanism for private landlords** (see Decision 9). Deferred
  until a safe authentication and anti-re-identification design is approved.
- **Behaviour of routes for removed/rejected reviews** — 404 vs. 410, indexing
  signals, cache invalidation. See `docs/ARCHITECTURE.md` §4.
- **Doxxing-sensitive address display rules** — whether `floor`, `door`, and
  geo coordinates are shown publicly, especially for single-occupant addresses
  and addresses associated with a private landlord. See
  `docs/SECURITY_RULES.md` §10 and `docs/DATA_MODEL.md` §6.
