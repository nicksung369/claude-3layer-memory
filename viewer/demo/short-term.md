# Short-Term Memory (48h Rolling)

> Last aggregated: 2026-04-17 18:00
> Sessions found: 4
> Window: past 48 hours

---

### 2026-04-17 — payments-api

## Session Summary

### Tasks
- Refactor the Stripe webhook handler to deduplicate on `event.id`
- Add idempotency key to all charge-create calls
- Fix flaky integration test `test_webhook_replay_is_noop`

### Files Modified
- `services/payments/webhooks.py`
- `services/payments/stripe_client.py`
- `tests/integration/test_webhook_replay.py`

### Tools Used
Read, Edit, Bash, Grep

---

### 2026-04-16 — payments-api

## Session Summary

### Tasks
- Investigate duplicate-charge incident from 2026-04-14
- Draft postmortem in `docs/incidents/2026-04-14.md`

### Files Modified
- `docs/incidents/2026-04-14.md`
