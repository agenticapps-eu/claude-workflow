---
phase: 23
plan: 1
subsystem: add-observability
tags: [cron-monitor, healthz, sigterm, migration-0019, guarded-shape-a, tdd]
dependency_graph:
  requires: [phase-22-sentry-crons-healthz]
  provides: [add-observability-0.7.0, guarded-shape-a-withcronmonitor, healthz-per-probe-timeout, split-trap-migration-0019]
  affects: [templates/ts-cloudflare-worker, templates/ts-cloudflare-pages, templates/ts-supabase-edge, templates/go-fly-http, migrations/0019-engine]
tech_stack:
  added: [ADR-0029, CHANGELOG.md, fixture-07-allow-partial]
  patterns: [Guarded-Shape-A-handlerStarted, split-trap-EXIT-INT-TERM, AbortController-clearTimeout, context-WithTimeout-DeadlineExceeded]
key_files:
  created:
    - add-observability/CHANGELOG.md
    - docs/decisions/0029-cron-monitor-sdk-composition.md
    - migrations/test-fixtures/0019/07-allow-partial-emits-patches/setup.sh
    - migrations/test-fixtures/0019/07-allow-partial-emits-patches/verify.sh
    - migrations/test-fixtures/0019/07-allow-partial-emits-patches/expected-exit
  modified:
    - add-observability/SKILL.md (0.6.0 -> 0.7.0)
    - add-observability/init/INIT.md
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts
    - add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts
    - add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts
    - add-observability/templates/ts-cloudflare-pages/cron-monitor.ts
    - add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts
    - add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts
    - add-observability/templates/ts-cloudflare-pages/healthz-snippet.test.ts
    - add-observability/templates/ts-supabase-edge/cron-monitor.ts
    - add-observability/templates/ts-supabase-edge/cron-monitor.test.ts
    - add-observability/templates/ts-supabase-edge/healthz-snippet.ts
    - add-observability/templates/ts-supabase-edge/healthz-snippet.test.ts
    - add-observability/templates/go-fly-http/cron_monitor.go
    - add-observability/templates/go-fly-http/healthz_snippet.go
    - add-observability/templates/go-fly-http/healthz_snippet_test.go
    - migrations/run-tests.sh
    - migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh
    - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
decisions:
  - "Guarded Shape A (ADR-0029): withCronMonitor composes Sentry.withMonitor with handlerStarted flag"
  - "F2 per-stack heterogeneous timeout: Worker 3rd-arg / Pages context.env / Supabase Deno.env / Go HealthzDeps field"
  - "Split trap: EXIT silent; INT exit 130; TERM exit 143 — separate handlers prevent cleanup leak on success"
  - "D-07 honest reframe: default refuse writes patches to DIRTY roots only; CLEAN roots not patched"
  - "TS AbortController + clearTimeout in try/finally (not Promise.race)"
metrics:
  duration: "~4 hours (2026-05-29)"
  completed: "2026-05-29"
  tasks_completed: 18
  files_changed: 25
  commits: 28
---

# Phase 23: add-observability 0.7.0 — observability followups Summary

Guarded Shape A withCronMonitor refactor + per-stack healthz timeout + SIGTERM split-trap + D-07 honest reframe, hardened by multi-AI review before execution.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 0.1 | Wave 0 dispatcher extension (R-rev-4) | 2ba0e71 | migrations/run-tests.sh |
| 0.2 | ADR-0029 (Guarded Shape A, Wave 0) | bd1337b | docs/decisions/0029-cron-monitor-sdk-composition.md |
| F1 | INIT.md per-stack composition notes | 03048b5 | add-observability/init/INIT.md |
| D-09 | sentry-go WithMonitor SDK gap note | 665656a | add-observability/templates/go-fly-http/cron_monitor.go |
| F4 RED | SKILL.md drift test — RED | 2f26f58 | migrations/run-tests.sh |
| F4 GREEN | SKILL.md drift test — GREEN | cec575e | migrations/run-tests.sh |
| F2 worker RED | healthz per-probe timeout worker — RED | d4910fa | ts-cloudflare-worker/healthz-snippet.test.ts |
| F2 worker GREEN | healthz per-probe timeout worker — GREEN | 9f267cb | ts-cloudflare-worker/healthz-snippet.ts |
| F2 pages RED | healthz per-probe timeout pages — RED | d4bad93 | ts-cloudflare-pages/healthz-snippet.test.ts |
| F2 pages GREEN | healthz per-probe timeout pages — GREEN | 46144fe | ts-cloudflare-pages/healthz-snippet.ts |
| F2 supabase RED | healthz per-probe timeout supabase — RED | ab26c1e | ts-supabase-edge/healthz-snippet.test.ts |
| F2 supabase GREEN | healthz per-probe timeout supabase — GREEN | 5ad5c6c | ts-supabase-edge/healthz-snippet.ts |
| F2 go RED | healthz per-probe timeout go — RED | eeacb9f | go-fly-http/healthz_snippet_test.go |
| F2 go GREEN | healthz per-probe timeout go — GREEN | f974ca4 | go-fly-http/healthz_snippet.go |
| F5 worker | Guarded Shape A worker (RED+GREEN) | 5fbe86a + 077eeba | ts-cloudflare-worker/cron-monitor.ts+test |
| F5 pages | Guarded Shape A pages (RED+GREEN) | a802bef + d354310 | ts-cloudflare-pages/cron-monitor.ts+test |
| F5 supabase | Guarded Shape A supabase (seam + RED + GREEN) | af381cb + 3a473d3 + b77958d | ts-supabase-edge/cron-monitor.ts+test |
| 3.1 F3 RED | SIGTERM split-trap + path validation — RED | 56630e3 | migrations/run-tests.sh |
| 3.1 F3 GREEN | SIGTERM split-trap + path validation — GREEN | ae18dea | migrate-0019 + run-tests.sh |
| 4.1 | D-07 audit 0017 (read-only) | 864ae92 | (empty commit) |
| 4.2 | D-07 0019 default-flip + fixture 07 | a3cfe3f | migrate-0019 + fixtures 06+07 |
| 5.1 | SKILL.md 0.6.0 -> 0.7.0 | 6b4067d | add-observability/SKILL.md |
| 5.2 | CHANGELOG.md 0.7.0 entry | ebcd6a4 | add-observability/CHANGELOG.md |
| 5.3 | Final verification | aa68152 | (empty commit) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] D-07 exit-code: ALLOW_PARTIAL path exited 2 instead of 0**
- **Found during:** Task 4.2 fixture 07 verification
- **Issue:** Final exit block exited 2 when dirty dirs present, even under --allow-partial (dirty dirs expected/skipped)
- **Fix:** Split exit check: only exit 2 on APPLY_FAILED; dirty-skipped-under-allow-partial exits 0
- **Commit:** a3cfe3f

**2. [Rule 1 - Bug] ALLOW_PARTIAL env var check read overwritten value**
- **Found during:** Task 4.2 ALLOW_PARTIAL env opt-in implementation
- **Issue:** Script set ALLOW_PARTIAL=0 before env check; ${ALLOW_PARTIAL:-} always returned 0
- **Fix:** Capture _ALLOW_PARTIAL_ENV="${ALLOW_PARTIAL:-}" before arg-parse block
- **Commit:** a3cfe3f

**3. [Rule 1 - Bug] F3 test cases 4c/4d false-failed on exit code**
- **Found during:** Task 5.3 full harness run
- **Issue:** Engine without --project-dir scanned repo root, found dirty test fixtures, exited 2 from all-clean gate (not path validation). Test checked exit code, not error message.
- **Fix:** Assert absence of path-validation error message in stderr instead of checking exit code
- **Commit:** a3cfe3f

**4. [Rule 3 - Blocking] Worktree branch diverged from feat branch across sessions**
- **Found during:** Session resumption after context compaction
- **Fix:** git merge --ff-only at session start and end
- **Impact:** Zero lost work

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

- add-observability/SKILL.md: version 0.7.0 confirmed
- add-observability/CHANGELOG.md: 0.7.0 entry present
- docs/decisions/0029-cron-monitor-sdk-composition.md: exists
- migrations/test-fixtures/0019/07-allow-partial-emits-patches/: all 3 files exist
- trap on_exit EXIT / trap on_int INT / trap on_term TERM: present in migrate-0019
- migrations/run-tests.sh: 181 PASS, exit 0
- Template harness: all stacks green, exit 0
