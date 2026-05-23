# Design Principles

Binding UX philosophy and interface-governance rules for **RML**.

This document is **not** a visual design spec, a brand book, or a component
library. It is the *why* and *must-not* of the interface — the rules that any
future `docs/DESIGN.md`, component system, design tokens, or page layout must
respect.

RML publishes statements about identifiable parties to people making financial,
legal, and life-significant decisions. The interface is part of how the
platform earns trust and avoids harm. Aesthetic decisions are subordinate to
clarity, scanability, and moderation visibility.

These rules are binding until explicitly revised here. Where this document
conflicts with a future visual or component decision, this document wins.

---

## 1. Core philosophy

RML's interface follows a small set of non-negotiable commitments. Each is
operational, not aspirational.

- **Trust-first UI.** Every screen makes it clear *what is on it*, *who said
  it*, *when*, and *whether it has been moderated and verified*. If the user
  cannot answer those four questions at a glance, the screen has failed.
- **Utility before branding.** The product is a tool for tenants and the
  reviewed parties — not a marketing surface. The brand layer is restraint
  and consistency, not personality.
- **Clarity over novelty.** Familiar patterns are preferred to clever ones.
  When a familiar pattern is wrong for the content, replace it; do not
  decorate it.
- **Evidence-oriented design.** Structured facts (rent, deposit return,
  mould, dates) lead. Narrative free text supports them. Photos illustrate;
  they never replace structured fields.
- **Calm over engagement.** RML is read in moments of stress — a tenant
  comparing properties, a reviewer recalling a bad tenancy. The interface
  does not amplify that stress with urgency cues, animation, or attention
  bait.
- **Reduce renter anxiety, do not amplify it.** Concretely: never use
  countdowns, social-proof spikes, "X people are looking at this", or visual
  alarm states for non-alarming information. Reserve the destructive /
  warning colour for genuine problems.
- **Honest information density.** Showing more useful data on one screen is
  better than hiding it behind clicks, provided readability holds. Whitespace
  is a tool, not a virtue.
- **Moderation is part of the product, not a hidden function.** A reader
  must always be able to see whether content is approved, pending,
  verified, edited, or under review (see §4).
- **Accessibility is a baseline, not a configuration.** The default
  experience is accessible; "accessibility mode" toggles or AAA-only
  alternates are not the answer.

---

## 2. Information density

RML is a comparison and decision tool. Layouts are dense by intent and
readable by discipline.

### 2.1 Spacing discipline

- The base spacing unit is **4 px**. All vertical and horizontal rhythm is a
  multiple of 4 (4, 8, 12, 16, 24, 32). Arbitrary px values are not used.
- The standard page container is **`max-w-screen-xl`** (≈ 1280 px) with
  responsive horizontal padding. Wider hero-style centred columns are
  forbidden outside of legal/marketing-prose pages.
- A page's primary heading is followed by **8–16 px** of margin before
  content, not 64 px. Section breathing room comes from content rhythm, not
  large blank zones.
- Cards and rows use the smallest padding that preserves readability:
  **12–16 px** for compact contexts (search results, comparison rows),
  **16–24 px** for primary content cards. Never 48 px.
- Whitespace is *between groups*, not *inside groups*. A group of related
  fields stays visually adjacent; the separation lives between unrelated
  groups.

### 2.2 Typography hierarchy

- One H1 per route, derived from the route's subject (the address, the
  company, "Log in"). Decorative supertitles and "welcome to" phrases are
  forbidden.
- The type scale is tight on purpose (see `tailwind.config.ts`): body is
  `15px / 24px`, H1 is `24–30px`. The scale supports density; do not
  inflate it for marketing weight.
- Numbers (ratings, rent, deposit, area, m², dates) use **tabular figures**
  wherever they appear in a list or table. Misaligned digits read as careless.
- Long-form free text is rendered in a **measure-restricted column**
  (60–75ch). Free text is the secondary view; structured fields lead.
- Section labels (e.g. "Ratings", "Issues", "Deposit") are uppercase or
  small-caps **only when they are genuine column labels** in dense data; in
  flowing pages, sentence-case headings are preferred.

### 2.3 Scanability

- Every list row exposes the **same three signals** in the same place:
  identifier, rating/score, and the one most decision-relevant fact (e.g.
  deposit-return outcome). Variable card shapes per row are forbidden.
- The visual order of information matches the **decision order** — what does
  this person need to know first? Aesthetic groupings that defy the decision
  hierarchy are wrong.
- Mixed units (DKK, m², stars, dates) keep consistent placement across rows
  and pages. A user who has learned that "rent is on the right" should never
  be retrained.
- Truncation is **last-line ellipsis** with a clear "more" affordance. Never
  truncate a number or a status. Never truncate without indicating it.

### 2.4 Cards, lists, tables

- **Lists** are the default for review collections and search results. Each
  row is one review or one entity.
- **Cards** are used when a row needs structural grouping (e.g. a review
  with sub-ratings, deposit info, and photos). Cards have minimal chrome:
  a thin border, modest internal padding, no shadows beyond a 1 px elevation.
- **Tables** are used on the address and company pages for comparison views
  (multiple reviews side-by-side). Tables on RML are first-class — not
  hidden behind "advanced view". They use tabular figures, sticky headers
  on long pages, and a clear sort affordance.
- No card has a "hero image". A photo, if present, is a constrained tile,
  not a full-bleed banner.

---

## 3. Search & discovery UX

Search is the entry point and the most-used surface (see
`docs/PRODUCT_DECISIONS.md` §5 and §7). It is engineered for *fast,
trustworthy comparison*, not exploration.

### 3.1 Address search

- The primary search input is **persistent in the header** on every public
  page after the landing page. The landing page also surfaces it
  prominently, but not as a giant hero — a single input row at typical
  body width.
- **Autocomplete is structured**, not free-text. Results show the matched
  fragment, the full address, and (where known) a quick trust signal
  (e.g. number of reviews). Results are bounded (see
  `docs/SECURITY_RULES.md` §6).
- Minimum prefix length, opaque cursor pagination, and rate limiting are
  enforced server-side. The UX hides this; the UI does not display a
  "you are being rate-limited" banner unless the user is actually blocked.
- Empty states explain *why* nothing was found in operational language
  ("No reviews yet for this address" — not "Oops! 0 results 😢"). Empty
  states never advertise other content to fill space.

### 3.2 Company lookup

- Companies are searchable by name and CVR. The UI displays CVR alongside
  name in every result row — CVR is the unambiguous identifier and helps
  users distinguish similarly-named companies.
- A company row shows: name, CVR, number of approved reviews, aggregate
  rating, and `status` (active / dissolved). Dissolved companies are not
  hidden; they are clearly labelled.
- There is **no public profile page for a private individual landlord**
  (see `docs/PRODUCT_DECISIONS.md` §10). The search UI does not encourage
  searching by person name; a person-name query falls back to address
  search.

### 3.3 Filters and sorting

- **Sorting is explicit and labelled.** "Recommended" / "Best match" sort
  modes are forbidden when their ordering logic is not documented to the
  user. Default sort is the most useful documented order (e.g. "Newest
  reviews"); the user can switch to a clearly named alternative.
- The active filter set is **always visible** above the results — chip-style
  pills the user can dismiss individually. Hidden, sticky, or persistent
  filters that the user cannot see are forbidden.
- Sub-rating filters (deposit returned, mould, communication) are surfaced
  early because they map to decision pressure points. Aesthetic filters
  ("colour scheme", emoji moods) are forbidden.
- An empty filtered result set says exactly which filter is causing the
  empty state and offers to remove it.

### 3.4 Trust indicators and issue visibility

- Each result row carries a small, accessible **verification badge** (when
  the badge mechanism is approved — see
  `docs/PRODUCT_DECISIONS.md` open questions). The badge is text-and-icon,
  not icon-only.
- Severity icons or chips for issues (mould, deposit dispute, harassment)
  use the **same set of labels and the same colour mapping everywhere**
  they appear. A given issue never has different names or colours on
  different pages.
- Aggregate ratings on a result row include the **review count** with the
  same prominence. A 5-star rating from 1 review is not visually identical
  to a 5-star rating from 30 reviews.

### 3.5 Fast comparison

- On address and company pages, the **table comparison view** is one click
  (or one keystroke) away from the list view, not three. Comparing reviews
  is a primary use case.
- A user who selects multiple reviews to compare gets a **side-by-side
  layout**, not a modal carousel. Modals are reserved for confirmations and
  short tasks.
- Comparison views show the same structured fields across all selected
  reviews in the same row order. The user does not have to re-scan to find
  the deposit field in each card.

---

## 4. Moderation visibility

Moderation is core product (see `docs/MODERATION_POLICY.md`). The interface
must make moderation legible to ordinary readers — not hide it.

### 4.1 Visible status

- Every public-facing piece of user content (review, photo, reply) displays
  its **moderation state** when that state matters: typically `verified`,
  `unverified`, `edited`, or `under review`. The state appears next to the
  content's author/date metadata, not in a hidden panel.
- `pending`, `rejected`, and `removed` content **never** appears on a public
  page (see `docs/SECURITY_RULES.md` §1). The author, however, sees their
  own pending content with clear status on their account page.
- The author's view of their own review shows: current public version,
  current revision status if any, and the moderation history at a high
  level (submitted → approved → edited → resubmitted → approved). Without
  the moderation log, the author cannot understand what happened.

### 4.2 Verification communication

- A **verified** badge means: a moderator confirmed, via documentation, that
  the reviewer was a real tenant of that address during that period (see
  `docs/DATA_MODEL.md` §4). The badge's tooltip and the legal pages explain
  this precisely.
- **Unverified** is the default and is shown as such — not absent. Hiding
  the unverified state would let users assume verification by default.
- The verification badge is **never colour-only**. It is text-and-icon, with
  enough contrast to be visible to colour-blind users.

### 4.3 Edits and revisions

- A published review that is later edited displays an **"edited" label**
  with the date of the most recent approved revision. The previous
  approved version is the public version until the new revision is
  re-approved (see `docs/DATA_MODEL.md` §3.1).
- The label is not a link to a diff for the public reader. It is a signal.
  Moderators see the diff in the moderation surface.
- Silent edits are forbidden in the product, in the model, and in the UI.

### 4.4 Removed and disputed content

- A review that was published and then removed shows a **clear, neutral
  notice**, not a 404, when reached by direct link. The notice explains
  *that* it was removed and the broad reason category (e.g. "removed
  following a moderation review"). It never names the reporter or the
  decision rationale in detail.
- A review under active dispute (open report being investigated) does
  **not** show "this review is being investigated" to the public — that
  invites pile-on. It continues to display normally until the moderator
  decides. The reviewer and the moderation team see the dispute state.
- Behaviour for `404 vs 410` and indexing signals is an open product
  question (see `docs/PRODUCT_DECISIONS.md` open questions). The UI is
  designed so that the eventual decision drops in cleanly.

### 4.5 Reporting and right-of-reply

- The "report this review" action is **discoverable but not prominent** —
  available next to the review, not floated as a primary CTA. Excessive
  visibility invites abuse.
- The reporting form requires a **structured reason** (see
  `docs/DATA_MODEL.md` §2.10). Free text is optional and short. The UI
  never implies that submitting a report will get content removed; the
  language is neutral.
- The right-of-reply (`company_replies`) display is **clearly attributed**
  to the reviewed company (name + CVR), placed below the review, and
  visually distinct so the reader sees who is speaking. Company replies do
  not change the review's rating or moderation status (see
  `docs/MODERATION_POLICY.md` §6).

---

## 5. Accessibility

RML's accessibility baseline is **WCAG 2.2 Level AA**. AAA where reasonable.
The default experience is accessible; an "accessibility mode" toggle is not
acceptable.

### 5.1 Contrast and colour

- Body text contrast against its background is **≥ 4.5:1**. Large text
  (≥ 18.66 px regular or 14 px bold), UI components, and graphical objects
  meet **≥ 3:1**.
- Status colours (approval, error, info, verification) are **never
  conveyed by colour alone**. Each carries an icon, a label, or both.
- The default palette is restrained (see §7). Decorative colour is
  avoided; functional colour (destructive, ring, muted-foreground) is
  scoped to its purpose.

### 5.2 Keyboard navigation

- Every interactive element is reachable and operable via keyboard.
- **Focus is always visible.** The global `:focus-visible` style uses a 2 px
  ring offset by 2 px (already wired in `globals.css`). Removing the focus
  ring is forbidden.
- Tab order follows the visual reading order. `tabindex="-1"` is used only
  for programmatic focus targets (e.g. dialog containers), never to skip
  controls.
- Modals, comboboxes, and menus implement a **focus trap** and restore
  focus to the trigger on close.
- Keyboard shortcuts (e.g. `/` for search) are documented on the page that
  uses them and do not override standard browser keys.

### 5.3 Motion

- The CSS reset already honours `prefers-reduced-motion: reduce`. New
  animations must respect it.
- Motion is used for **state continuity** (an element moving from A to B),
  not for decoration. Duration is **≤ 200 ms** for state changes; 400 ms
  ceiling for the rare layout transition.
- Loading skeletons may animate (`tailwindcss-animate`), but not at
  attention-grabbing frequencies. No pulsing CTAs.
- Auto-playing motion, parallax, marquee, and looping animations are
  forbidden.

### 5.4 Touch targets

- Interactive controls have a touch target of **≥ 44 × 44 px** (Apple HIG)
  and ideally **48 × 48 px** (WCAG 2.5.5 AAA target). Hit areas may be
  larger than the visible control.
- Adjacent controls have **≥ 8 px** of space between hit areas to avoid
  mistaps.

### 5.5 Typography

- Minimum body size is **15 px** (the configured base). The scale does not
  go below 12 px outside of fine-print legal contexts.
- Line length is **45–75 characters** for long-form prose. Dense data
  tables may be tighter.
- Line height is at least **1.5×** for body text; **1.2×** is acceptable
  for headings and dense tabular content.
- Letter-spacing is not used to "improve" body text. It is reserved for
  the rare uppercase label.

### 5.6 Screen readers

- All images have meaningful `alt` text, or `alt=""` if they are decorative
  (review photos use descriptive alt; status icons are typically `aria-hidden`
  with adjacent text).
- Status changes (form errors, async operations completing) are announced
  via `aria-live` polite regions. Modals are properly labelled with
  `aria-modal` and `aria-labelledby`.
- Form controls have explicit labels — `placeholder`-only labels are
  forbidden.
- Icons that carry meaning have `aria-label`; icons that decorate text get
  `aria-hidden="true"`.

### 5.7 Language

- The `lang` attribute on `<html>` matches the active locale (Danish or
  English). Mixed-language passages set `lang` on the element.
- Error messages and status text are localised in both Danish and English
  (see `CLAUDE.md` §9).

---

## 6. Responsive philosophy

RML is **mobile-first but desktop-strong**. The mobile breakpoint is where
volume is; the desktop breakpoint is where comparison happens.

### 6.1 Breakpoints (matching Tailwind defaults)

- **base**: ≤ 639 px (mobile).
- **`sm`**: 640 px.
- **`md`**: 768 px (tablet).
- **`lg`**: 1024 px (desktop).
- **`xl`**: 1280 px.
- **`2xl`**: 1280 px (container cap; we do not stretch beyond this).

### 6.2 Information preservation across breakpoints

- The **structured fact** is the unit of hierarchy. A fact that appears at
  desktop must appear at mobile, even if reformatted. We do not "simplify
  for mobile" by dropping facts that affect decisions — rent, deposit
  outcome, mould, dates, verification badge, moderation state are present
  at every breakpoint.
- What changes across breakpoints is **layout** (table → stacked rows),
  **density** (more padding on touch surfaces), and **secondary navigation**
  (visible nav → collapsed menu). The decision-critical content stays.
- "Read more" / expandable rows on mobile are acceptable for narrative
  free text, never for structured facts.

### 6.3 Desktop comparison

- The desktop comparison view (multi-review side-by-side, sortable table)
  is a first-class layout, not a derivative of the mobile card stack. It
  is designed natively for the wider breakpoint.
- Sticky headers and column-pinning are used in long comparison tables.
  The user should not lose orientation while scrolling.

### 6.4 Mobile considerations

- The bottom of the viewport is more reachable than the top on a phone.
  Primary actions on long forms are placed accordingly (e.g. submit
  button visible without scrolling, or pinned).
- The search input is one tap from any public page.
- Tap-and-hold gestures are not the only way to access any function. A
  visible affordance always exists.

---

## 7. Visual direction

A restrained Scandinavian-inspired neutral baseline. Not a brand statement —
a constraint.

### 7.1 Palette

- The default palette is the warm-neutral **stone** family already wired in
  `globals.css`. Light and dark modes share the same tokens; the design is
  built for both from day one.
- One **accent colour** is used sparingly — for the primary affordance and
  focus ring. The accent is not present on every screen.
- **Destructive** is reserved for genuinely destructive or alarming
  information (deletion confirmations, severe issues like significant
  mould). It is not used to drive attention to neutral content.
- Decorative colour (illustrations, mood gradients, "fun" accent
  rotations) is forbidden.

### 7.2 Surfaces

- Surfaces are flat or near-flat. Shadows are reserved for elevated
  components (popovers, dialogs), and even then are minimal — a single
  soft shadow, not stacked elevation levels.
- Borders carry most of the structural work: 1 px borders in the muted
  border colour are the default separator between cards, rows, and
  sections.
- Glassmorphism, blur effects, frosted overlays, and translucent layers
  are forbidden outside of full-screen modal scrims.

### 7.3 Typography is the visual identity

- The system font stack does the work. No custom display fonts. If a
  custom font is added later, it is one sans-serif for body and headings,
  chosen for legibility on Danish characters (æ, ø, å) and at small sizes.
- Headings differ from body by **weight and size**, not by colour or
  decoration.

### 7.4 Iconography

- A single icon family (Lucide, already configured) is used throughout.
  Mixing icon libraries is forbidden.
- Icons are **24 px** in dense UI, **20 px** in inline contexts. They do
  not become a decorative element.

### 7.5 Imagery

- The only first-party imagery is user-uploaded review photos (mould,
  damage, condition). Stock photography is not used.
- Review photos are presented at controlled aspect ratios within the card,
  never as full-bleed banners (see §2.4).
- No illustrations of "happy people in apartments" or other generic
  emotional imagery.

### 7.6 Animation

- See §5.3. Animation is functional, brief, and reduced-motion-aware. The
  default state of the interface is still.

---

## 8. Components and interaction principles

These are the binding behaviours for the major UI elements. Specific token
values live in the future `docs/DESIGN.md`; the *rules* live here.

### 8.1 Forms

- Labels are visible and above the input. Placeholder-only labels are
  forbidden.
- Help text appears below the input, in muted foreground, **always
  present** when relevant (not only on focus).
- Validation errors appear below the input in the destructive colour,
  with a clear icon, in plain language. Field-level errors and
  form-level errors coexist; the form-level summary lists field-level
  problems with anchor links.
- Required fields are marked with a clear, non-decorative indicator
  (asterisk + `aria-required`).
- Multi-step forms (review submission) show a **progress indicator** with
  step names, not just step numbers. Steps are revisitable.
- A long form's primary submit is **persistent**: visible at the bottom of
  the form and pinned where it helps.
- Destructive actions in forms (delete account, withdraw review) require
  a typed confirmation, not just a button click.

### 8.2 Review cards

- A review card shows, in this order from top to bottom: header
  (verification badge, date, moderation state if relevant), overall
  rating, structured key facts (rent, deposit return, mould, tenancy
  period), issue chips, photos (if any), optional free text, company
  reply (if any).
- The verification badge and moderation state never live below the
  fold.
- The author's pseudonymous display name is shown small and muted — it
  is identity confirmation, not the headline.
- Photos in a card open in a focused lightbox with a single, short-lived
  signed URL (see `docs/SECURITY_RULES.md` §3). The lightbox is keyboard-
  navigable and has visible close.

### 8.3 Search results

- Each result row uses the same skeleton (see §2.3). Address rows, company
  rows, and review rows each have a fixed skeleton; the skeleton is the
  same across pages.
- Highlighting of matched query fragments is **subtle** — a weight bump or
  underline, not a coloured background.
- Pagination is **explicit** — next/previous and a page indicator. No
  infinite scroll on public listings (see §9).

### 8.4 Filters

- Filters live in a sidebar on desktop and a slide-over sheet on mobile.
  Either way, the **active set is visible** as chips above the result
  list (see §3.3).
- A filter never silently changes the sort.
- Filter values that filter to zero are not hidden — they are shown
  disabled with a "0" count, so the user understands why nothing matches.

### 8.5 Moderation labels

- Moderation labels (`pending`, `verified`, `edited`, `removed`) use a
  consistent visual treatment: a small text-and-icon chip in a muted
  surface. They are **legible from a normal viewing distance**, not
  microcopy.
- Status colours match across the product: verified and edited are
  neutral/positive (no green explosion); pending is muted; under-review
  is shown only to relevant parties (see §4.4).

### 8.6 Uploads

- The upload area shows: accepted formats (`image/jpeg`, `image/png`,
  `image/webp` for photos; +`application/pdf` for verification), the
  size limit (10 MB photos / 15 MB documents — see
  `docs/SECURITY_RULES.md` §3), and what will happen with the file.
- Photo uploads display an in-progress moderation badge until approved
  (visible to the author only).
- Verification document uploads carry a **prominent privacy notice**
  explaining what is collected, what it is used for, and the retention
  posture (see `docs/SECURITY_RULES.md` §8).
- Drag-and-drop is supported but never the only path; a file picker
  button is always present.

### 8.7 Navigation

- The site header is a **single horizontal bar** containing the brand
  link, the persistent search input (on non-landing pages), and primary
  links (max ~5 items). It does not collapse into a hamburger at
  desktop; mobile uses a slide-over.
- Footer carries legal links (privacy, terms, imprint, takedown info —
  see `docs/ARCHITECTURE.md` §4) and is plain and minimal.
- Breadcrumbs are used on address and company pages where the hierarchy
  is real (e.g. address → review). They are not decorative on flat
  routes.

### 8.8 Status messaging

- **Toast notifications** are used for transient confirmations
  ("Review saved", "Photo uploaded"), not for critical errors. They auto-
  dismiss in 4–6 seconds and are announced via `aria-live="polite"`.
- **Inline messages** are used for persistent status (form errors,
  page-level notices). They do not auto-dismiss.
- **Banners** at the top of a page are used for cross-page status (e.g.
  "Your account has unresolved verification") — rare, neutral, dismissible
  per session.
- No dialogs that interrupt the user with unrelated information ("Did
  you know..."). Modals are reserved for confirmations, focused tasks,
  and content the user opened intentionally.

### 8.9 Destructive actions

- Destructive actions (delete review, delete account, remove photo)
  always require an explicit confirmation step with the destructive
  colour, the verb spelled out ("Delete review", not "Confirm"), and —
  for account deletion — a typed confirmation (`docs/SECURITY_RULES.md`
  §7 GDPR erasure).
- The destructive action is never the default-focused button in a
  dialog. The safe action is the default.
- Undo is provided where it is technically possible and legally safe.

---

## 9. Anti-patterns

The following are forbidden in RML. They will be rejected during review
even if they are technically functional and pretty.

- **Aesthetic-usability bias.** Polished but unscanable layouts are
  worse than unpolished, scanable ones.
- **Giant marketing heroes.** Full-viewport hero sections, oversized
  taglines, and image-led splash zones on the landing page.
- **Decorative dashboards.** Aggregate counters and "stats" panels that
  exist to look impressive rather than inform a decision.
- **Fake urgency / fake scarcity.** "X people viewed this address",
  countdowns, "only 2 left", "limited reviews remaining", or any
  manufactured pressure.
- **Engagement bait.** Streaks, badges for daily visits, gamification
  of review submission, "you might also be interested in" upsells.
- **Infinite scroll on public listings.** Search results, address-page
  review lists, and company-page review lists use explicit pagination.
- **Hidden sort logic.** Unnamed "recommended" / "smart" / "best" sorts.
- **Deceptive ratings displays.** A 5-star average from 1 review shown
  with the same visual weight as a 5-star average from 100. Aggregated
  visuals that imply more reviews than exist.
- **Hidden moderation states.** Edits that don't disclose themselves,
  removed content rendered as 404 with no explanation, verification badges
  that imply more than they actually mean.
- **Hidden filter persistence.** Filters that persist invisibly between
  sessions, sticky filters the user can't see.
- **Unreadable low-density layouts.** "Premium" empty layouts where you
  scroll past a 60vh hero to read three sentences.
- **Excessive onboarding friction.** Multi-step welcome flows, "tell us
  about yourself" pre-product surveys, modal tours.
- **Decorative animation.** Floating elements, parallax, scroll-jacking,
  mouse-tracking visuals, hover-triggered movement.
- **Glassmorphism, gradient overlays, neon accents, "AI startup"
  visuals.** RML is a public-interest review tool, not a fintech demo.
- **Dark patterns.** Confusing toggles, opt-out-by-default for data
  uses, preselected upsells, "are you sure you don't want…" guilt
  modals, asymmetric destructive/safe action prominence.
- **Manipulative engagement copywriting.** "Tenants like you also…",
  "Don't miss out", "Last chance", anthropomorphic mascots, emoji-led
  empty states.
- **Auto-playing video or audio.** Anywhere.
- **Modals for non-tasks.** "Welcome back!", "Did you know we have a
  blog?", "Rate the new design".
- **Colour-only status.** Green dot / red dot without a label.
- **Placeholder-only labels.** Empty inputs with `placeholder` doing
  the work of a label.
- **Microcopy that hides what's happening.** "Oops!", "Something went
  wrong", emoji-laden errors. Errors are factual and actionable.

If a future feature seems to need one of the above, the answer is to
revisit the feature, not to relax the principle.

---

## 10. Relationship to future `docs/DESIGN.md`

This document defines **UX philosophy and governance**. It does not
define visual tokens, component APIs, spacing scales (beyond the
4-px base unit), or specific colour values (beyond pointing at the
restrained-stone baseline already in `globals.css` and
`tailwind.config.ts`).

A future `docs/DESIGN.md` will implement the principles defined here:

- concrete design tokens (colour HSL values, spacing scale, radii,
  border weights, motion durations);
- the component inventory and API surface (variants, sizes, states,
  composition rules);
- the relationship between the tokens, Tailwind config, and shadcn-style
  primitives in `src/components/ui/`;
- icon usage rules at the per-icon level;
- accessibility patterns at the per-component level (ARIA attributes,
  keyboard maps).

`docs/DESIGN.md` must not contradict this document. Where a token or
component requirement conflicts with a principle here, this document
wins until it is revised. New principles or revisions to existing ones
go into this document, not into `docs/DESIGN.md`.

When `docs/DESIGN.md` is created:

- it is referenced from `CLAUDE.md` §11 and from `docs/ARCHITECTURE.md` §3;
- it is updated in the same change as any design-token or component-API
  change (the same documentation-duty discipline as the rest of the
  governance docs — see `CLAUDE.md` §10).

Until `docs/DESIGN.md` exists, the principles here, plus the scaffolded
defaults in `tailwind.config.ts` and `src/app/globals.css`, are the
working visual system.
