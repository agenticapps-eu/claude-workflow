---
phase: 27
plan: "02"
subsystem: observability-templates
tags: [test-coverage, buildSentryOptions, tdd, sentry, cf-worker, cf-pages, openrouter]
dependency_graph:
  requires: []
  provides: [WR-03]
  affects: [27-05]
tech_stack:
  added: []
  patterns: [direct-unit-coverage, sensitivity-proof-via-mutation, token-template-aware-tests]
key_files:
  created: []
  modified:
    - add-observability/templates/openrouter-monitor/src/observability/index.test.ts
    - add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts
    - add-observability/templates/ts-cloudflare-pages/lib-observability.test.ts
decisions:
  - "Token-aware assertions: cf-worker/cf-pages tests hardcode materialized values (SENTRY_DSN, test-service, 0.1) rather than token strings — harness substitutes before vitest runs"
  - "Sensitivity via mutation not committed RED: flipped sendDefaultPii=true locally, observed 2 failures in Tests A+B, reverted before commit"
  - "MED-4 preserved: D-02a block comment references buildSentryOptions only in the pre-existing 'NO dependency' comment — zero functional calls"
metrics:
  duration_minutes: 15
  completed_date: "2026-06-02"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 3
requirements: [WR-03]
---

# Phase 27 Plan 02: buildSentryOptions Direct Unit Coverage Summary

**One-liner:** Direct `buildSentryOptions(env)` unit tests (Tests A/B/C) added to all 3 stacks (openrouter, cf-worker, cf-pages) with sensitivity proven via temporary `sendDefaultPii=true` mutation, locking the Blocker-C corrected contract (sample rate is baked constant, not env-derived).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add buildSentryOptions coverage (correct assertions) + sensitivity proof | 7af2e07 | openrouter index.test.ts, cf-worker lib-observability.test.ts, cf-pages lib-observability.test.ts |
| 2 | Verify all 3 stacks GREEN through materialization harness | (no commit — verification only) | — |

## What Was Built

Added a `describe("buildSentryOptions", …)` block to each of the 3 stacks that export the helper:

**Test A** — all env fields set: asserts `dsn`, `environment`, `release`, `tracesSampleRate`, `sendDefaultPii` match exactly.

**Test B** — `DEPLOY_ENV` and `SERVICE_NAME` absent: asserts `environment === "dev"`, `release === SERVICE_DEFAULT` (`"openrouter-monitor"` for openrouter, `"test-service"` for cf-worker/cf-pages via harness), and the other 3 fields correct.

**Test C** — constant-not-override: passes `{ SENTRY_DSN: "d", TRACE_SAMPLE_RATE: "0.99" } as any` and asserts `tracesSampleRate === 0.1` — proves the rate is a scaffold-time constant, not runtime env-parsed (RESEARCH Blocker-C correction).

**Token-template handling:** cf-worker and cf-pages test files use the materialized identifiers (`SENTRY_DSN`, `DEPLOY_ENV`, `SERVICE_NAME`, `"test-service"`, `0.1`) — the harness substitutes `{{ENV_VAR_DSN}}` → `SENTRY_DSN` etc. before vitest runs, so the tests are correct both as token templates and after materialization.

## Sensitivity Proof (§06 Evidence)

Temporary local mutation: `sendDefaultPii: false` → `sendDefaultPii: true` in openrouter's `buildSentryOptions`. Result:

```
❯ src/observability/index.test.ts (4 tests | 2 failed) 5ms
  × buildSentryOptions > returns the correct SentryOptions shape when all env fields are set
    → expected true to be false // Object.is equality
  × buildSentryOptions > falls back to defaults when DEPLOY_ENV and SERVICE_NAME are absent
    → expected true to be false // Object.is equality
```

Tests A and B caught the mutation immediately. Test C was unaffected (it only asserts `tracesSampleRate`). Mutation reverted before commit. The helper implementation is unchanged in the committed artifact.

## Verification Results

| Stack | Command | Result |
|-------|---------|--------|
| openrouter | `npx vitest run` (direct) | 17 passed (2 files) |
| ts-cloudflare-worker | `bash run-template-tests.sh ts-cloudflare-worker` | 93 passed (7 files) |
| ts-cloudflare-pages | `bash run-template-tests.sh ts-cloudflare-pages` | 78 passed (5 files) |

## Acceptance Criteria

- [x] `describe("buildSentryOptions"` block present in all 3 named target files (verified per-file)
- [x] Test C (`tracesSampleRate is a baked constant`) present in all 3 files
- [x] MED-4: D-02a block has zero functional dependency on `buildSentryOptions` (only a comment)
- [x] No deliberately-false assertion: `grep '\.not\.toBe(0\.1)' --include='*.test.ts'` → empty
- [x] Single coverage commit: `git log --oneline -1 --grep 'add buildSentryOptions coverage'` → `7af2e07`
- [x] All 3 stacks GREEN via harness

## Deviations from Plan

None — plan executed exactly as written.

The "openrouter" stack ID used in the plan's verify block (`bash run-template-tests.sh openrouter`) is not a valid harness stack name. The harness requires `ts-cloudflare-worker` / `ts-cloudflare-pages`; openrouter is directly testable via `npx vitest run`. Executed both paths accordingly — this is a plan documentation issue, not an implementation deviation.

## Known Stubs

None. All assertions use real, wired values.

## Threat Flags

None. Test-only additions; no production code, no new network endpoints, no auth paths, no schema changes.

## Self-Check: PASSED

Files exist:
- FOUND: add-observability/templates/openrouter-monitor/src/observability/index.test.ts
- FOUND: add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts
- FOUND: add-observability/templates/ts-cloudflare-pages/lib-observability.test.ts
- FOUND: .planning/phases/27-1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum-/27-02-SUMMARY.md

Commits exist:
- FOUND: 7af2e07 (test(27-02): add buildSentryOptions coverage × 3 stacks)
