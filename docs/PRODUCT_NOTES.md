# Product Notes

A lightweight, evolving thinking space for RML's product direction.

This file is **not** a specification, a roadmap, or a backlog. It's a place
for half-formed ideas, open questions, UX concerns, and the kind of
exploratory thinking that doesn't yet belong in the binding governance
docs. If you've got a thought about how a flow could feel, a question
nobody has answered, or a worry about a user we haven't talked about
enough — write it here. Don't worry about putting it in the "right"
section. Capture matters more than structure.

It's safe to:

- write things that aren't fully formed
- ask questions without proposing answers
- contradict yourself between sections — leave both versions if they're
  in honest tension; don't force a synthesis you don't believe yet
- add a one-line note and move on
- challenge an assumption that's elsewhere documented as decided
- come back later and rewrite a section that turned out to be wrong
- delete or shorten a section you wrote yourself last week

You don't need permission to add a thought. Drop it in roughly the
right section (or just under *Open questions* if you're not sure),
tag it, and keep going.

This applies to both human contributors and AI assistants. Structure
may evolve; that's expected.

> **How this differs from the other docs.** Anything in
> `PRODUCT_DECISIONS.md`, `SECURITY_RULES.md`, `MODERATION_POLICY.md`,
> `DESIGN_PRINCIPLES.md`, `DATA_MODEL.md`, `ARCHITECTURE.md`, or
> `API_INTEGRATIONS.md` is **binding** — written down, reviewed,
> revisable only by an explicit change to that doc. This file is the
> opposite: revisable freely, never the source of truth for an
> implementation rule. When something here matures into a real decision,
> it graduates to one of the binding docs and gets removed (or
> retrospectively linked) from here.

Tags used through this file:

- **[implemented]** — already exists in the codebase or schema.
- **[direction]** — what we're currently leaning toward, not yet built.
- **[open]** — genuine open question, no decision yet.
- **[future]** — interesting idea we might never do.

---

## How we currently think

A few orienting principles we keep coming back to. Not a manifesto —
just the lean of the project right now. These will resurface when a
specific question gets stuck:

- **Trust over engagement.** A user who comes once, finds what they
  needed, and leaves is the win condition. Daily-active anything is
  not the goal.
- **Calm usefulness over outrage.** RML is a tool for a stressful
  decision, not a place to vent. Calm is the value proposition.
- **Clarity over growth hacks.** No streaks, badges, nudges,
  notification loops, "you might also like" upsells.
- **Protect users before optimising anything.** Anti-doxxing,
  pseudonymity, and pre-publication moderation are floor, not
  feature requests.

These are slow to change. If one of them starts to feel wrong,
that's worth its own entry under *Open questions* below.

---

## Vision

RML is a tool for tenants in Denmark who are about to sign a lease.
Their decision is high-stakes (a year or more of their life, a large
deposit, a place to live), the information available to them is thin
(landlord references are absent, online reviews are scattered, word of
mouth is unreliable), and the asymmetry is uncomfortable: the landlord
knows everything about the prospective tenant; the tenant knows almost
nothing about the landlord.

We want to make that asymmetry less brutal — without becoming a
weapon. The product is useful when it helps a tenant make a *concretely
better* decision (this address has had two reviewers report severe
mould; this company returned deposits in full every time; this private
landlord is unresponsive in writing). It is harmful when it amplifies
bad-faith claims, doxxes individuals, or invites retaliation.

The first version of RML should feel calm, honest, and small. A
careful reviewer's notebook, not a rage forum.

---

## A way to think (when stuck)

When a product question feels abstract, ground it in a *moment* — not
a persona, just a small slice of someone's day. The point isn't to
design the moment; it's to let the abstract question land somewhere
concrete so the next sentence is easier to write.

A few moments that keep showing up for us:

- **Sunday, 23:00.** A tenant has been offered a place. They're
  signing tomorrow. They paste the address into RML on their phone.
  What's on screen in the first three seconds? What do they need to
  see *before* they scroll?
- **The angry reviewer.** A tenancy just ended badly. The reviewer
  opens the form, tired, still upset. The structured fields are easy
  to fill. The free-text field is open. What does the wording above
  it say? What does the *submit* button promise?
- **Monday morning, the moderator.** Six pending reviews in the
  queue. One is flagged high-risk. The moderator has fifteen minutes
  before a meeting. What's on screen at-a-glance that lets the first
  decision happen with confidence?
- **The landlord who found their company on RML.** A small Danish
  rental company sees their CVR-page for the first time. The first
  review is critical but fair. They want to reply. What's the path
  from "found it" to "submitted a reply" — and how does it feel when
  the reply doesn't appear immediately because moderation is real?
- **The tenant who's halfway through.** A current tenancy where
  things are getting worse. The tenant wants to start a draft now and
  finish it when the deposit comes back. Does the product even let
  them do that yet? Should it?

Add a moment to a section when it helps the section land; remove the
moment when the section moves on. Moments are scaffolding, not
deliverables.

---

## Current product direction

Roughly, in order of "we're confident" → "we're still figuring out":

- **The structured review is the unit.** Stars + factual fields +
  amounts + dates + issue tags do most of the work. Free text is
  optional and reviewed more strictly. [implemented in schema,
  PRODUCT_DECISIONS §4]
- **Companies first, private landlords with caution.** CVR-identified
  companies get public profile pages and replies. Private individual
  landlords don't. Reviews involving them attach to the address.
  [implemented in schema, PRODUCT_DECISIONS §10]
- **Pre-publication moderation for everything.** No content is public
  until a human approves it. [implemented in schema,
  PRODUCT_DECISIONS §3]
- **Pseudonymous public identity.** Reviewer's real identity is never
  exposed; the snapshot of the pseudonymous handle survives even after
  account deletion. [implemented in schema, PRODUCT_DECISIONS §2]
- **Search-as-product.** The address search is the product, not a side
  feature; the 10-second-find target drives the UI choices.
  [direction; not yet implemented as a UI]
- **Verification is a separate, lighter signal.** A small text-and-icon
  badge, no evidence detail exposed. [direction; the badge state exists
  in the schema, the evidence-review workflow doesn't yet]

---

## Core flows (as we're thinking about them)

### Read flow

> A prospective tenant pastes / types an address into the homepage
> search → autocompletes within a few keystrokes → lands on an address
> page with structured aggregates + a list of approved reviews →
> scans, decides whether to dig in.

What we like about this:
- One canonical surface per address. No fragmentation across "listings".
- Most of the information is in structured fields they can scan; free
  text is the optional colour.

What we're less sure about:
- How aggressive can autocomplete be without becoming a doxxing channel
  for partial addresses? **[open]** The rate-limit + min-prefix rules in
  `SECURITY_RULES.md` §6 are the first answer.
- Address pages where a building has many tenants vs. addresses where
  a single household lives behind a single door — the same UI may
  feel different. **[open]**

### Write flow

> A tenant decides to leave a review → must sign up first → form is
> structured (ratings, amounts, enums, tags) with free text optional →
> submitted as pending → moderator reviews → approved / rejected /
> resubmission-needed.

What we like:
- Account required = accountability behind the scenes.
- Structured-first = less emotion, fewer defamation traps.
- Pre-publication moderation = nothing harmful goes live by accident.

What we're less sure about:
- Onboarding friction. Sign-up before review submission may lose
  emotional momentum from people who came specifically to vent. Is
  that a feature (we don't want the vent-ers) or a bug (we lose
  signal)? **[open]**
- Should we offer a "save draft, finish later" path? Useful for tenants
  whose tenancy just ended and who want to come back with deposit-return
  details once they know. **[future]**
- How do we handle "I'm halfway through my tenancy and the situation
  has changed" — submit now and update later via a revision, or wait?
  The schema supports revisions; the UX hasn't decided yet. **[open]**

### Moderation flow

> A moderator opens the queue → sees pending reviews ordered by
> submitted_at (high-risk first) → for each, can approve, reject with
> a structured reason, or mark for verification → every action writes
> a `moderation_events` row.

What we like:
- One queue, one place. No hidden flags.
- Every action is logged; the moderation history is auditable internally.
- Append-only `moderation_events` removes the entire class of
  "moderation cover-up" failure modes. [implemented in schema]

What we're less sure about:
- Capacity. v1 will likely have one moderator (the maintainer). What's
  the queue-depth signal before that becomes a problem? **[open]**
- How much moderation context to show the moderator at-a-glance. Too
  little = bad decisions; too much = decision paralysis. **[open]**
- Whether moderators should be able to "request edit" (send back to
  the author with a structured suggestion) vs. only approve/reject.
  The revision-workflow schema technically supports this if we add a
  `pending → needs_changes` state — but right now we just have
  reject-and-resubmit. **[future]**

### Reply flow (CVR companies only)

> A company that's been reviewed wants to respond → identity-verified
> representative submits a reply → moderation queue → approved reply
> shows alongside the review.

What we like:
- Right-of-reply is real fairness for companies.
- Keeps the platform balanced and reduces legal exposure.

What we're less sure about:
- The whole rep-verification mechanism is a giant **[open]** —
  `replies_insert_disabled` blocks all reply writes today. Options:
  a per-company representative table; a service-role-only path with
  out-of-band verification; a CVR-OAuth-style flow via MitID. We
  haven't chosen.

---

## Implemented (today)

A quick reality check before the speculative sections that follow.
Just what actually exists in the repo right now:

- The v1 schema migration (`supabase/migrations/2026...sql`):
  tables, RLS, public views, freezing of approved reviews,
  append-only `moderation_events`, snapshot-based public reviewer
  identity, 90-day verification retention default.
- Seeded local dev dataset (`supabase/seed.sql`).
- Auth skeleton: email + password sign-up, sign-in, sign-out,
  cookies-based sessions, auth-aware header, server-side role gate on
  `(admin)/`. Schema-side trigger creates profiles on signup.
- A `public-data` debug page that reads only `public_*` views and
  renders them as flat tables.
- Governance: CLAUDE.md, ARCHITECTURE.md, DATA_MODEL.md,
  SECURITY_RULES.md, MODERATION_POLICY.md, PRODUCT_DECISIONS.md,
  API_INTEGRATIONS.md, DESIGN_PRINCIPLES.md, SCHEMA_REVIEW.md.

Not implemented but referenced everywhere: review submission UI,
search UI, moderation queue UI, signed-URL minting route, retention
sweeper job, address/CVR import pipeline, first-admin bootstrap RPC.

---

## Open questions (the genuine ones)

These don't yet have answers. Adding one here doesn't commit anyone to
resolving it on any timeline.

- **Tenancy verification.** The schema supports verification documents
  (lease, bill, deposit receipt) and a 90-day retention default, but
  the workflow isn't designed: when does a reviewer get prompted to
  verify? Is it gated (no review without verification) or optional
  (an extra trust badge)? Who reviews the evidence — same moderator
  pool, or a smaller verified group? What does "good enough evidence"
  look like operationally?
- **Onboarding friction vs. signal quality.** Account requirement +
  structured form may lose the people who'd write the most useful
  reviews (busy people leaving mediocre tenancies). Is there a path
  that lowers friction without lowering quality? Pre-fill from a
  search query? Mobile-first form layout?
- **Emotional safety for the reviewer.** A tenant submitting a critical
  review may worry about retaliation from the landlord. Pseudonymity
  protects identity, but does the *act* of leaving a review feel safe?
  What language do we use in the submit flow to make the reviewer feel
  protected? Do we explain the moderation process? Is there a "you
  can edit/withdraw this later" reassurance we should surface?
- **What happens when a reviewed party disputes a published review.**
  Reports mechanism exists in the schema; the UX of "this review is
  contested" doesn't exist. We've said we don't show "under
  investigation" publicly (avoids pile-on). But what's the moderator's
  decision SLA? Open in PRODUCT_DECISIONS.md.
- **Highly-occupied buildings vs. single-household addresses.** A
  review at `Eksempelgade 5, 2200 København N` could be:
    (a) "one of forty tenants in a block" — anonymity is structural;
    (b) "the only tenant in a single-family house" — the review
        effectively names the household.
  We don't currently distinguish (a) from (b) in the UI. Does the
  product behave differently in case (b)? Refuse to publish? Show with
  a warning? Aggregate-only?
- **Private landlord experience in the product.** We've decided not to
  give them public profile pages. But the same person might be a
  *reviewer* (their own previous tenancy) AND a *reviewee* (someone
  reviews them). The current product doesn't acknowledge that overlap.
- **How long does a review stay relevant?** A 2017 review of a building
  whose owner sold in 2020 to a different company — is that still
  useful? Showing? Filtered? Soft-archived?
- **Internationalisation beyond Danish + English.** Tenants in Denmark
  include large communities of Polish, Romanian, Arabic, Ukrainian,
  English-as-second-language speakers. v1 is da/en. Worth tracking
  whether that's a real exclusion or acceptable for v1.

---

## UX / trust considerations

The product publishes opinions about identifiable parties to people in
the middle of a financial decision. Trust is the whole game.

Things we keep coming back to:

- **Visible moderation state.** A reader should be able to tell
  whether a review has been verified, edited, or is awaiting
  re-moderation. The schema supports this; the UI components don't
  exist yet. The `is_edited` boolean and `verification_status` are
  ready to surface.
- **No engagement loops.** No streaks, no "your review got 12 helpful
  votes today" notifications. That whole class of UX is forbidden
  (`DESIGN_PRINCIPLES.md` §9). The reviewer's reward should be the
  feeling of having warned the next tenant — not platform-mediated
  social validation.
- **Sober tone.** No emoji, no marketing copy, no "you might also like".
  This is a tool that someone uses once during a stressful decision.
  Calm is the value proposition.
- **Errors and rejections that respect the reviewer.** If a moderator
  rejects, the rejection message should be useful (here's what doesn't
  meet policy) rather than blank. The structured-reason field on
  `moderation_events` is the data substrate; the UX is **[open]**.
- **Anti-doxxing in defaults.** `public_addresses` doesn't expose
  floor/door/geo; that's a design choice that the schema enforces.
  We should keep checking that new surfaces don't accidentally
  re-expose this kind of information.

---

## Features we've already decided not to do (yet)

Listed here so we don't keep re-litigating them in chat:

- OAuth providers other than email/password (no MitID, no Google).
- Account deletion via UI (the schema supports it; the flow doesn't
  exist).
- Right-of-reply for private individual landlords. Deferred —
  `replies_insert_disabled` policy holds.
- Push notifications, email digests, weekly summaries — anything that
  pulls users back into the platform on a schedule.
- "Helpful" / "Unhelpful" votes on reviews. Tempting but invites
  pile-on.
- Public moderation log. The log exists and is private. Making it
  public turns the platform into a meta-courtroom.

---

## Future ideas (uncommitted)

Brain dumps. Nothing here is on a roadmap.

- A landlord-portal where companies can verify ownership of an
  address (BBR lookup) and add a context note to their profile. Not
  a reply to a specific review — a one-line "we changed deposit-return
  policy in 2024" kind of note.
- Aggregated city-level trends ("median deposit in Aarhus C in 2024:
  ...") drawn from approved reviews. Privacy implications heavy;
  thresholds matter.
- A reviewer's "draft tenancy log" tool — let them privately note
  things during their tenancy (mould first noticed on $date), then
  pull the log into a review at the end. Could increase signal
  quality dramatically. Probably needs its own privacy story.
- Address-page subscribe (with explicit opt-in): a tenant looking
  at an address gets notified once if a new review is published.
  Email-only, not push. Maybe.
- Move-out checklist generation from the tenancy data, with
  reminders about Danish-specific deadlines (deposit-return windows,
  utility cut-off). Useful adjacency; probably its own product.

---

## Current focus

What the maintainer is actually working on right now (this section is
short by design — long lists here become aspirational backlogs):

- Getting the foundational read path solid (schema, public views,
  the dev test page).
- Making the auth skeleton browsable end-to-end so the moderation
  surface can be built next.
- After that: review submission form against the v1 schema.

---

## Meta — how this file is meant to evolve

A few things to keep in mind as this file grows:

- **It will probably get reorganised.** Sections may be split, merged,
  renamed. Items may move from `[open]` to `[direction]` to a binding
  doc as decisions mature.
- **AI assistants may help.** It's fine for an AI helper to suggest a
  cleaner grouping, pull duplicate ideas together, or move a settled
  decision over to `PRODUCT_DECISIONS.md` with a link. Big structural
  refactors should be reviewed by the maintainer before they land.
- **No promotion without checking.** Moving something from this file
  to a binding governance doc is a real change. Even if the idea has
  been here for months, the binding doc needs an explicit "this is
  now decided" moment.
- **Don't delete history casually.** If an open question gets a
  decision, the question stays here briefly as `[resolved, see
  PRODUCT_DECISIONS.md §N]` so we don't lose the *journey* of the
  thought.

If you're an AI assistant reading this in a future session and the
file feels messy — that's expected. Suggest a cleaner structure in
your reply; don't unilaterally reorganise.
