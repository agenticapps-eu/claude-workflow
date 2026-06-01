---
status: partial
phase: 26-worker-template-hardening
source: [26-VERIFICATION.md]
started: 2026-06-01T14:00:00Z
updated: 2026-06-01T14:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. ADR-0034 narrative correctness
expected: Read `docs/decisions/0034-observability-init-singleton-invariant.md` end-to-end. ADR follows ADR-0029/0030/0033 shape; explicitly cites isolate-REUSE (not "reset between invocations"); explains last-call-wins vs first-call-wins shapes per stack; D-02b coverage of `initialized` flag + `_testEnv` test seam is explicit and accurate; rejected-alternatives section explicitly names the prior framing.
result: [pending]

### 2. env-additions.md operator wiring snippet quality
expected: Read each updated `env-additions.md` (cf-worker, cf-pages, openrouter-monitor). Snippet present: `export default withSentry(env => buildSentryOptions(env), withObservability(handler));`. Import path matches file layout. Explains env-purity rationale clearly. Mentions `@sentry/cloudflare >= 8.0.0` dep requirement.
result: [pending]

### 3. CHANGELOG UPGRADE NOTE clarity (T1 mitigation)
expected: Read `add-observability/CHANGELOG.md` 0.10.0 entry UPGRADE NOTE. Operators with existing `policy.md` clearly directed to manually review/update REDACTED_KEYS section. No automated migration path mentioned. Lists 4 new entries (`authorization`, `bearer`, `cookie`, `x-api-key`).
result: [pending]

### 4. .gitignore provenance header phrasing
expected: Read each new `.gitignore` header (5 files). cf-worker + cf-pages cite Phase 24 openrouter-monitor precedent + Phase 26 extension. Non-Cloudflare stacks (supabase-edge, react-vite, go-fly-http) explain runtime-conventional defaults + flag [ASSUMED] items.
result: [pending]

### 5. WR-04 — openrouter-monitor entry file does NOT use buildSentryOptions
expected: Decide whether to update `add-observability/templates/openrouter-monitor/src/index.ts` to actually call `buildSentryOptions(env)`. Currently the entry file inlines the options object literally — the helper is exported but unused in the openrouter scaffold itself. Either (a) update src/index.ts to use the helper as a demonstration, or (b) tighten env-additions.md / CHANGELOG language to clarify the helper is for downstream consumers but openrouter-monitor is a worked-example for cron-monitor not buildSentryOptions.
result: [pending]

### 6. WR-03 — buildSentryOptions has zero direct test coverage
expected: Decide whether to add direct buildSentryOptions tests. Codex MED-4 decoupling forbids using DEF-1 inside DEF-3 tests but does NOT forbid a standalone DEF-1 test. Suggested: add 4-assertion unit test per stack covering env-derived dsn/environment/release + baked tracesSampleRate + sendDefaultPii:false + fallback to defaults when env absent. Would catch regressions like `sendDefaultPii: true` or `release: env.DEPLOY_ENV` copy-paste swaps.
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps
