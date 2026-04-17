---
name: Mobile merge freeze 2026-04-16
description: No non-critical mobile merges after Apr 16 — iOS release branch cut
type: project
---

Merge freeze begins 2026-04-16 for the mobile release branch cut.

**Why:** Mobile team is shipping the Liquid Glass refresh to TestFlight on
2026-04-22 and needs a stable branch for QA.

**How to apply:** Any PR touching `app/ios/**` or `app/android/**` scheduled
after 2026-04-16 should be flagged as "post-freeze" unless tagged
`hotfix-*`. Backend PRs are unaffected.
