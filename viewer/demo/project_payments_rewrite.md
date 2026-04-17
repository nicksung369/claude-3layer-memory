---
name: Payments idempotency rewrite
description: Rewriting webhook + charge-create to dedupe on event.id — compliance-driven
type: project
---

Full rewrite of the Stripe webhook handler and charge-create path to be
idempotent on `event.id`.

**Why:** The 2026-04-14 duplicate-charge incident was traced to a retry loop
that used `(account_id, created_at)` as the dedup key. Legal flagged the
downstream refund work as a compliance exposure.

**How to apply:** Scope decisions should favor compliance over ergonomics —
if a change makes the dedup key weaker, block it. Target merge date:
2026-04-25. Owner: Jamie. Reviewers: Priya, Dax.
