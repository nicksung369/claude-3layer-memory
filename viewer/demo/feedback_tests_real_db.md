---
name: Integration tests must hit a real database
description: No mocked DBs — prior mock/prod divergence masked a broken migration
type: feedback
---

Integration tests must hit a real Postgres via testcontainers, not mocks.

**Why:** In 2025-Q4 a mocked test suite went green while the prod migration
silently dropped a NOT NULL constraint. Mocks diverged from real schema for
~6 weeks before the incident.

**How to apply:** Any PR touching `services/**` with tests must show either
`testcontainers` imports or a Docker-based fixture. Flag mock-only DB tests
as blocking review comments.
