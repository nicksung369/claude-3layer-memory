# Long-Term Memory

> Permanent keystones. Only entries that survived two promotion cycles.

## Infrastructure

- Primary region: `us-east-1`. DR region: `us-west-2`. Replication is async with ~3s lag.
- All Postgres migrations gated through `pgroll` — never raw `ALTER TABLE` in prod.
- Service mesh is Linkerd 2.x; timeouts configured per-route in `mesh/routes.yaml`.

## Team Conventions

- Squash-merge only. Commit subject = PR title. No "Co-Authored-By" trailers.
- Feature flags owned in LaunchDarkly. Kill-switch flags prefixed `kill_*`.
- Integration tests hit a real Postgres (testcontainers), never mocks.

## Payment Domain Invariants

- One charge per `(idempotency_key, account_id)` — enforced at the DB level.
- Webhook handlers must be idempotent by `event.id`. Retries are expected.
- Refunds never bypass the state machine in `services/payments/state.py`.
