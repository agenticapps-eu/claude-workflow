# fixture-edge

A minimal Supabase Edge Functions project for testing the
`add-observability init` procedure against the `ts-supabase-edge` stack.

<!-- agenticapps:observability:start -->
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
  policy: supabase/functions/_shared/observability/policy.md
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
<!-- agenticapps:observability:end -->
