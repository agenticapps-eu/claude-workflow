# fixture-vite

A minimal Vite + React SPA for testing the `add-observability init`
procedure against the `ts-react-vite` stack.

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
