# fixture-worker

A minimal Cloudflare Worker for testing the `add-observability init`
procedure against the `ts-cloudflare-worker` stack.

<!-- agenticapps:observability:start -->
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
  policy: src/lib/observability/policy.md
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
<!-- agenticapps:observability:end -->
