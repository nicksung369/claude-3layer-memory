# Medium-Term Memory (2-Week Digest)

> Window: 2026-04-03 → 2026-04-17
> Sessions: 23  ·  Projects: 3

## Active Projects

- **payments-api** — idempotency rewrite (owner: Jamie) — 14 sessions
- **mobile-app** — iOS 26 Liquid Glass refresh (owner: Priya) — 6 sessions
- **internal-tools** — on-call rotation UI (owner: Dax) — 3 sessions

## Files Most Edited

1. `services/payments/webhooks.py` — 8 edits
2. `services/payments/stripe_client.py` — 6 edits
3. `app/ios/Views/CheckoutSheet.swift` — 5 edits
4. `tools/oncall/schedule.ts` — 4 edits

## Key Decisions

- Adopted `event.id` as dedup key over `(account_id, created_at)` tuple
- Pinned Stripe API version to `2025-11-20` across all services
- Paused mobile merges after 2026-04-16 — release branch cut
