# fixture-pages

A minimal Cloudflare Pages project for testing the `add-observability init`
procedure against the `ts-cloudflare-pages` stack.

<!-- agenticapps:observability:start -->
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
  policy: functions/_lib/observability/policy.md
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
<!-- agenticapps:observability:end -->
