# fixture-stdmux

A minimal Go net/http service for testing the `add-observability init`
procedure against the `go-fly-http` stack — std net/http router branch.

<!-- agenticapps:observability:start -->
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
  policy: internal/observability/policy.md
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
<!-- agenticapps:observability:end -->
