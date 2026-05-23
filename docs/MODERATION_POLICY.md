# Moderation Policy

Moderation policy for **RML**. This document defines what moderators enforce and
how moderation features must behave. It is binding for the moderation area and for
any code that creates, publishes, or removes review content.

RML publishes statements about identifiable parties. Moderation is the main control
that keeps the platform fair, lawful, and useful. It is treated as core product,
not as cleanup.

---

## 1. Pre-publication moderation

- Every review is moderated **before** it is publicly visible. New reviews are
  `pending` and not shown on public pages or counted in aggregates until `approved`.
- The same applies to **photos** and to **company replies** — each is moderated
  before publication and can be approved or rejected independently.
- A review may be approved for publication while still `unverified`: moderation
  (is this publishable?) and verification (was the reviewer a real tenant?) are
  **separate decisions**.

### 1.1 Published reviews are frozen; edits trigger a new cycle

- Once a review is `approved`, the published version is **frozen**. The
  reviewer cannot silently change what the public sees.
- Any **material edit** by the author — changes to ratings, structured factual
  fields (rent, deposit, deposit return, mould, issue categories, tenancy
  dates), the free-text body, or attached photos — creates a new `pending`
  revision. The previously approved version stays public until the new
  revision is moderated and `approved`. If the new revision is `rejected`,
  the previously approved version remains public.
- A resubmission writes a `review_resubmitted` event into `moderation_events`,
  followed by the eventual `approved` or `rejected` event.
- Photos that are added or replaced go through their own `pending → approved`
  cycle independently of the review body.
- Revision history is retained where practical so moderators can compare
  versions; see `docs/DATA_MODEL.md` §3.1.

---

## 2. What moderators reject or remove

Content in the following categories is rejected before publication, or removed if
already public:

- **Doxxing / private contact details** — phone numbers, private email or home
  addresses, social media handles, or other personal identifiers of any party.
- **Threats and incitement** — threats of violence, harassment, or calls to harm
  a landlord, company, employee, or other tenant.
- **Discriminatory content** — content attacking people on the basis of ethnicity,
  religion, nationality, gender, sexuality, disability, or similar.
- **Unverifiable criminal accusations** — allegations of crime presented as fact
  without basis. Tenants may describe their own experience; they may not publish
  unsubstantiated criminal charges against named parties.
- **Irrelevant rants** — content that is not about the tenancy experience: personal
  vendettas, off-topic complaints, content about unrelated parties.
- **Spam and manipulation** — fake reviews, review bombing, promotional content,
  duplicate submissions.

When rejecting, the moderator records a structured reason (see §7). Where the issue
is fixable, the reviewer should be able to edit and resubmit rather than lose the
review entirely.

---

## 3. Prefer structured factual claims over emotional accusations

- Moderators favour content framed as **specific, factual, first-hand experience**:
  "the deposit was returned three months late and reduced by 8,000 DKK with no
  itemised reason" is publishable; "this landlord is a criminal who steals from
  everyone" is not.
- The structured form is the primary, lower-risk content (see
  `docs/PRODUCT_DECISIONS.md`). Free text is reviewed more strictly.
- Where a free-text passage makes a strong claim, moderators check it is framed as
  the reviewer's own experience, is specific, and is not a sweeping accusation
  against a named individual.

---

## 4. High-risk free text

- Free text flagged as **high-risk** — criminal accusations, allegations against
  named individuals, emotionally charged claims — is never auto-published. It is
  held for closer human review (see `docs/PRODUCT_DECISIONS.md` Decision 8).
- The `is_high_risk` flag on a review (see `docs/DATA_MODEL.md`) marks these for
  the moderation queue. Detection may start as keyword/heuristic based; it must
  fail safe — uncertain content is flagged, not skipped.
- A high-risk review can still be published if, on review, the claims are framed
  as legitimate first-hand factual experience and do not breach §2.

---

## 5. Photos

- Photos are moderated before publication, independently of the review text.
- Reject photos that: identify a person without basis (faces, identifiable private
  individuals), show documents containing personal data, contain visible contact
  details, are unrelated to the dwelling, or are offensive/abusive.
- Photos should depict the **dwelling and its condition** (e.g. mould, damage,
  disrepair) — not people.
- Verification documents are **never** treated as review photos and never appear
  publicly (see `docs/SECURITY_RULES.md` §8).

---

## 6. Company replies

- Replies use the right-of-reply mechanism (`company_replies`) and are
  submitted by a verified representative of a reviewed **CVR-identified
  company**. There is **no** equivalent reply mechanism for private individual
  landlords in the initial product (see `docs/PRODUCT_DECISIONS.md` §9).
- Replies are **moderated before publication**, under the same standards as
  reviews: no threats, no doxxing of the reviewer, no discriminatory content,
  no attempt to identify a pseudonymous reviewer.
- A reply must not retaliate against or attempt to unmask the reviewer. Such
  replies are rejected.
- A reply does not change the review's rating or moderation status; it is
  displayed alongside the review.

---

## 7. Reported reviews

- Any user can report a published review or reply, choosing a structured reason
  (false, doxxing, harassment, spam, off-topic, other) — see `docs/DATA_MODEL.md`.
- A report opens a `reports` record and routes the target into the moderation queue.
- A moderator reviews the report and resolves it: keep, edit, or remove the content.
  The outcome is recorded.
- Report handling must resist abuse: a flood of reports against one review does not
  auto-remove it; volume informs prioritisation, a moderator makes the decision.
- Reporter identity is private and never shown to the reviewed party or the public.
- A valid takedown request (e.g. from a rights holder or named party) is handled
  through the same queue with appropriate priority.

---

## 8. Moderation event log

- **Every moderation action writes a `moderation_events` record** —
  submission, approval, rejection, removal, verification review, reply
  approval, report resolution, role assignment/change, review resubmission,
  and access to verification evidence.
- The log is **append-only and immutable**: events are never edited or deleted.
- Each event records the actor, the target, the event type, a structured
  reason, and the status transition.
- The log is **private** — it is internal accountability data, never shown
  publicly.
- Accessing a verification document is itself a logged event.
- Append-only behaviour is enforced at the database: no `UPDATE` and no
  `DELETE` policies are created (denying both operations under RLS), and a
  defensive trigger raises on `UPDATE` and `DELETE`. Service-role code does
  not bypass this. See `docs/SECURITY_RULES.md` §1.
- A correction to an earlier decision is a **new event** that supersedes the
  earlier one. The earlier event is never modified.

---

## 9. Moderator conduct and access

- Moderator and admin roles are assigned through a controlled path and never
  self-granted by a client.
- Moderators access private data (verification documents, reporter identity, real
  reviewer identity) only as needed to do the task, and that access is logged.
- Moderation decisions should be consistent with this document; significant
  judgement calls or new patterns are discussed and, if they set a precedent,
  written into this policy.

---

## 10. Relationship to other documents

- Product-level rules behind moderation: `docs/PRODUCT_DECISIONS.md`.
- Data isolation, evidence handling, RLS: `docs/SECURITY_RULES.md`.
- Status fields and the event-log schema: `docs/DATA_MODEL.md`.
- The moderation area as architecture: `docs/ARCHITECTURE.md` §6.
