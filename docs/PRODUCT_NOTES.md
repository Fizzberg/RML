# Product Notes

## Table of contents

- [How to use this file](#how-to-use-this-file)
- [Scratchpad / inbox](#scratchpad--inbox)
- [Emerging flows](#emerging-flows)
- [Current direction](#current-direction)
- [Reality check](#reality-check)
- [Foundation](#foundation)
- [Maintenance](#maintenance)

---

## How to use this file

This document is intentionally temporary and messy.

The goal is not polished documentation.
The goal is to capture thinking before it disappears.

Ideas from here may later become:
- flows
- governance decisions
- moderation policy
- UX notes
- technical implementation
- or be deleted entirely

Capture first.
Structure later.

Short notes are fine.
Contradictions are fine.
Half-formed thoughts are fine.

Sections are containers, not rules.
If something is in the wrong place, it can be moved later.

Use tags when useful:
- `[direction]`
- `[open]`
- `[future]`
- `[ai]`
- `[ai-expanded]`

Unmarked notes are assumed to come from normal human discussion.

If AI introduces a substantially new idea or heavily expands one,
tag it with `[ai]` or `[ai-expanded]`.

---

# Capture

## Scratchpad / inbox

Put quick raw thoughts here.

- A moderation system that is too aggressive may suppress legitimate
  tenant experiences.

- There may eventually be a tension between legal safety and emotional
  honesty in reviews.

- We probably need to think carefully about what happens when a landlord
  disputes a review.


---

# Active work

## Emerging flows

These are becoming more concrete but are still evolving.


### Review submission flow

> User signs up → fills structured review form →
> moderation checks happen →
> review is published / flagged / held back.

Current lean:
- structured-first
- free text secondary
- moderation before publication
- low friction if possible


### Automatic moderation flow

Current lean:
- avoid human review for every low-risk post

Traffic-light direction:
- green = publish immediately
- yellow = publish + internal flag
- red = hold back + explain why

Goals:
- low friction
- legal safety
- emotional safety
- protection against harassment/misuse

Not final policy yet.


### Read/search flow

> User searches address →
> lands on address page →
> scans structured reviews quickly.

Current lean:
- address search is core product
- structured information should be fast to scan
- free text should support, not dominate


### Moderator flow

> Moderator opens queue →
> reviews flagged/high-risk items →
> approves/rejects/requests verification.

Current lean:
- append-only moderation history
- one moderation queue
- moderation actions logged

---

## Current direction

- Structured reviews should do most of the work.

- Free text should be optional and more strictly moderated.

- Pseudonymous public identity feels important.

- Search is probably the core product surface.

- The product should stay calm and useful rather than engagement-driven.

- Verification should probably become a lightweight trust signal rather
  than a huge gamified system.

- Private landlords should likely be treated more carefully than
  CVR-linked companies.


---

# Reality / scope

## Implemented today

### Infrastructure

- local Supabase setup
- v1 schema migration
- RLS
- public views
- seed dataset


### Auth

- signup/login/logout flow
- session refresh middleware
- role-gated admin routes
- pseudonymous profiles


### Development/testing

- public-data debug page
- governance + architecture docs


### Implemented in schema only

- moderation events
- verification retention rules
- company replies
- reports system


### Referenced but not implemented

- review submission UI
- search UI
- moderation queue UI
- retention sweeper
- address/CVR import pipeline
- first-admin bootstrap RPC


---

## Not now

- OAuth providers other than email/password
- Account deletion UI
- Right-of-reply for private landlords
- Push notifications / engagement loops
- Helpful/unhelpful votes
- Public moderation log
- MitID integration

---
# Meta

## Maintenance

- Reorganise sections when needed.
- Keep contribution friction low.
- Promote mature decisions into governance docs.
- Delete bad ideas freely.
- AI helpers may suggest restructuring.
- This document is expected to evolve heavily over time.
