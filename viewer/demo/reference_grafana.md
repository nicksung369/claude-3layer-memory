---
name: On-call latency dashboard
description: grafana.internal/d/api-latency — watched by on-call, pages on p99 > 800ms
type: reference
---

`grafana.internal/d/api-latency` is the primary on-call latency dashboard.

Check it when editing request-path code — a regression above p99 800ms pages
the on-call engineer within 5 minutes via the `api-latency-critical` alert.

Credentials via Okta SSO. No direct link sharing (board is internal-only).
