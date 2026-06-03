---
phase: 29-split-02-agenticapps-observability
plan: 04
subsystem: observability
tags: [cron-monitor, queue-monitor, sentry-flush, migration, tdd, fxsa-workers-6, adr-0036]

# Dependency graph
requires:
  - phase: 29-03
    provides: "Feature branch split-02-rename-and-0022, MIGRATIONS_VERSION at 1.20.0, migrations/run-tests.sh shim"
provides:
  - "cron-monitor.ts explicit-flush body (cf-worker + cf-pages + supabase-edge)"
  - "queue-monitor.ts explicit-flush body (cf-worker + cf-pages)"
  - "cron-monitor.test.ts + queue-monitor.test.ts rewritten to captureCheckIn+flush contract in both stacks"
  - "Immediate-flush regression test (FX-SIGNALS-WORKERS-6) in cron + queue suites (both stacks)"
  - "migrations/0022-explicit-flush-and-monitor-config.md (consumer axis 1.20.0->1.21.0)"
  - "migrations/scripts/migrate-0022.sh (FXSA-WORKERS-6 marker reconciliation)"
  - "migrations/test-fixtures/0022/ (5 fixtures including #61 real types.d.ts in fixture 04)"
  - "migrations/MIGRATIONS_VERSION bumped to 1.21.0"
  - "docs/decisions/0036-explicit-per-checkin-flush.md (supersedes ADR-0033 flush point)"
  - "All work on feature branch split-02-rename-and-0022 (NOT main)"
affects:
  - 29-05 (PR opens split-02-rename-and-0022 → main before v0.11.0 tag)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Explicit captureCheckIn + ctx.waitUntil(flush) per check-in (replaces withMonitor)"
    - "Two separate try/catch scopes for pre/post-handler distinction (no handlerStarted flag)"
    - "monitorConfig forwarded on every check-in (in_progress/ok/error)"
    - "Immediate-flush regression test: block handler on deferred promise; assert waitUntil(flush) already fired"
    - "0021 typecheck fixture pinned to frozen v1.20.0-templates (prevents live-template drift)"

key-files:
  created:
    - "~/Sourcecode/agenticapps/agenticapps-observability/docs/decisions/0036-explicit-per-checkin-flush.md"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0022-explicit-flush-and-monitor-config.md"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/scripts/migrate-0022.sh"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/test-fixtures/0022/ (5 fixtures + baselines)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-cloudflare-worker/package.json"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-cloudflare-pages/package.json"
  modified:
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-cloudflare-worker/cron-monitor.ts (withMonitor → captureCheckIn+flush)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts (rewritten to flush contract)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-cloudflare-worker/queue-monitor.ts (explicit flush)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-cloudflare-worker/queue-monitor.test.ts (rewritten to flush contract)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-cloudflare-pages/cron-monitor.ts (explicit flush)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts (rewritten)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-cloudflare-pages/queue-monitor.ts (explicit flush)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-cloudflare-pages/queue-monitor.test.ts (rewritten)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/ts-supabase-edge/cron-monitor.ts (explicit flush via flushFn seam)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/MIGRATIONS_VERSION (1.20.0 → 1.21.0)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/run-tests.sh (add test_migration_0022)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/verify.sh (pin templates to v1.20.0-templates snapshot)"

key-decisions:
  - "0022 to_version 1.21.0 on consumer axis (NOT 0.11.0 product version) — continues 0021's 1.20.0; writing 0.11.0 would downgrade consumers at 1.20.0"
  - "FXSA-WORKERS-6 marker recognised as reconcilable divergence in engine (INFO + apply, not REFUSE)"
  - "#61 fix (real @sentry/cloudflare types) lands ONLY in 0022/04 fixture — 0021/04 types.d.ts NOT modified (0021 immutable)"
  - "0021/04 verify.sh pinned to frozen v1.20.0-templates snapshot so 0021 typecheck doesn't drift with live template updates"
  - "supabase-edge cron-monitor uses flushFn seam (no ctx.waitUntil) — Deno isolate model audited as safe for direct flush"
  - "TDD red-green confirmed: 18 tests FAIL on old withMonitor body; 26 GREEN after explicit-flush implementation"

requirements-completed: []

# Metrics
duration: ~2h
completed: 2026-06-03
---

# Phase 29 Plan 04: Migration 0022 (explicit per-checkin flush) — Summary

**Deferred-fix migration 0022 (consumer axis 1.20.0→1.21.0) shipped: explicit captureCheckIn+flush replaces Sentry.withMonitor in cron-monitor + queue-monitor (FX-SIGNALS-WORKERS-6 race fixed), monitorConfig forwarded on every check-in (#61), and #61 real @sentry/cloudflare types land in 0022's own fixture; all 5 migration fixtures GREEN; full suite PASS=42 FAIL=0 XFAIL=4; drift passes on consumer axis (1.21.0==1.21.0).**

## Feature Branch

All work committed to `split-02-rename-and-0022` in the obs repo (NOT main).
Plan 05 opens the PR and merges before the v0.11.0 tag.

## Task 1: RED — Test Suite Rewrite

Rewrote all four test files to the captureCheckIn+flush contract before touching the implementation:

### Mock surface change

Old: `vi.mock("@sentry/cloudflare", () => ({ withMonitor: ... }))`
New: `vi.mock("@sentry/cloudflare", () => ({ captureCheckIn: ..., flush: ..., captureException: ... }))`

### Cases rewritten (cf-worker cron-monitor.test.ts — 16 → 15 tests)

| Old case (withMonitor contract) | New case (captureCheckIn+flush contract) |
|---|---|
| calls Sentry.withMonitor with slug + monitorConfig | calls captureCheckIn({in_progress}, monitorConfig) then {ok/error, checkInId} |
| handler return value through withMonitor callback | handler return value through (unchanged) |
| handler exception re-throws from withMonitor | handler exception → captureCheckIn({error}) + rethrow |
| DSN-unset no-op (withMonitor not called) | DSN-unset no-op (captureCheckIn not called) |
| D-08 guard: withMonitor throws BEFORE callback | D-08 guard: captureCheckIn throws → handler runs unmonitored |
| D-08 guard: withMonitor throws AFTER callback | Removed (structural scoping makes this implicit) |
| monitorConfig as 3rd arg to withMonitor (in_progress only) | monitorConfig forwarded on BOTH in_progress AND ok/error |

### NEW immediate-flush regression test (FX-SIGNALS-WORKERS-6)

Added in both stacks for cron AND queue:
```
Block handler on deferred promise → assert ctx.waitUntil(flush) ALREADY fired before handler resolves.
```
This pins the exact fix: after `captureCheckIn({in_progress})`, `ctx.waitUntil(Sentry.flush(2000))` fires
immediately — before the handler is awaited.

### Preserved (unchanged)

- D-16 CronMonitorSchedule type-level firewall (crontab + interval + string-rejection tests)
- D-05 strict-Env generic narrowing test (CallbotEnv interface without index signature, cf-worker only)
- D-10 queue-monitor multi-queue canonical-phrase regex test

### RED confirmation

- cf-worker: 18 tests FAIL, 8 pass (type-level tests pass, behavioral ones fail)
- cf-pages: 18 tests FAIL, 8 pass (same pattern)

**Commit:** `c6f162c`

## Task 2: GREEN — Explicit-flush implementation

Applied the authoritative body from RESEARCH-cron-monitor-flush-fxsa.md to all 5 template files:

### cf-worker + cf-pages cron-monitor.ts changes

```
FLUSH_TIMEOUT_MS = 2000
withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>(...):
  captureCheckIn({monitorSlug, status:"in_progress"}, monitorConfig)
  ctx.waitUntil(Sentry.flush(FLUSH_TIMEOUT_MS))  ← immediate (the fix)
  await handler(...)
  captureCheckIn({checkInId, monitorSlug, status:"ok"|"error"}, monitorConfig)
  finally: ctx.waitUntil(Sentry.flush(FLUSH_TIMEOUT_MS))
```

Key invariants:
- Narrowed generic `E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }` PRESERVED (ADR-0032/SC5)
- `handlerStarted` flag DROPPED (two try/catch scopes make pre/post distinction structural)
- `monitorConfig` forwarded on EVERY check-in (in_progress + ok + error)

### supabase-edge cron-monitor.ts

Applied the same captureCheckIn + flush body, using the existing test seam pattern:
- Added `flushFn` seam alongside `captureCheckInFn` (for Deno test suite)
- Uses `void flushFn(FLUSH_TIMEOUT_MS)` (not `ctx.waitUntil` — Pages/Edge has no ExecutionContext)
- Supabase Edge isolate model audited: per-invocation isolation; direct flush is safe

### queue-monitor.ts (cf-worker + cf-pages)

Applied identical explicit-flush treatment (supabase-edge has no queue-monitor — verified):
- `captureCheckIn({monitorSlug, status:"in_progress"}, monitorConfig)`
- `ctx.waitUntil(Sentry.flush(FLUSH_TIMEOUT_MS))` immediately
- `finally: ctx.waitUntil(Sentry.flush(FLUSH_TIMEOUT_MS))`

### GREEN confirmation

- cf-worker: 26 tests PASS (15 cron + 11 queue)
- cf-pages: 26 tests PASS (15 cron + 11 queue)

**Commit:** `eaa1254`

## Task 3: Migration 0022 + ADR-0036 + Fixtures + MIGRATIONS_VERSION

### ADR-0036 (docs/decisions/0036-explicit-per-checkin-flush.md)

Supersedes ADR-0033's flush point (guard semantics preserved; implementation changed from `withMonitor` to `captureCheckIn+flush`). Documents:
- SDK internals proof (IsolatedPromiseBuffer drains only on explicit flush)
- FX-SIGNALS-WORKERS-6 confirmed race
- Strict-Env generic preserved (not broadened to Record<string, unknown>)
- monitorConfig-on-every-checkin fix (secondary upsert race)

### Migration 0022 doc (from_version: 1.20.0, to_version: 1.21.0)

Consumer axis — continues the 1.x migration chain from 0021's 1.20.0. NOT the obs product version (0.11.0 would downgrade consumers). Three bundled fixes documented.

### migrate-0022.sh engine

Clones migrate-0021.sh's all-clean-gate + dirty-detection. Added:
- FXSA-WORKERS-6 marker recognition block (grep → INFO + treat as clean)
- v1.20.0 vs v1.21.0 baseline comparison (v1.20.0 baselines frozen in test-fixtures/0022/baselines/)

Security: no `/Users/` hardcoded paths; all vars quoted; never evals content; `grep -q` for marker check.

### Test fixtures (5)

| Fixture | What it tests |
|---------|---------------|
| 01-fresh-1.20.0-apply | Happy path: v1.20.0 wrapper → engine applies → v1.21.0 |
| 02-dirty-refuse | Non-FXSA hand-modification → REFUSE + .observability-0022.patch emitted |
| 03-already-1.21.0-skip | Twofold idempotency: cron hash v1.21.0 + queue present → SKIP_ALREADY |
| 04-strict-env-typecheck-flush-contract | D-18 SC5 end-to-end: strict CallbotEnv compiles with real @sentry/cloudflare types (#61 fix) |
| 05-fxsa-marker-reconciliation | FXSA-WORKERS-6 marker → INFO + apply (reconcilable divergence) |

**#61 fix in fixture 04:** `types.d.ts` declares `captureCheckIn` + `flush` + discriminated `MonitorConfig` (real @sentry/cloudflare shape). The released 0021/04 `types.d.ts` (which declares `withMonitor`) was NOT modified — 0021 is immutable.

### MIGRATIONS_VERSION bump

`version: 1.20.0` → `version: 1.21.0`

Drift test: `run_drift_test "$REPO_ROOT/migrations/MIGRATIONS_VERSION" "$REPO_ROOT/migrations"` → compares latest migration to_version (0022 → 1.21.0) against marker (1.21.0) → PASS.

### run-tests.sh addition

`test_migration_0022` function + dispatcher entry. Full suite result:
- **PASS=42, FAIL=0, XFAIL=4** (FIX-0017 known-deferred), drift PASS

### 0021/04 typecheck fix (Rule 1 - Bug)

After Task 2 updated live templates to v1.21.0, the 0021/04 fixture ran migrate-0021 which then copied the new captureCheckIn-based bodies — but the fixture's types.d.ts only knows withMonitor → tsc failure.

Fix: updated `0021/04/verify.sh` to pass `--templates-dir` pointing to a frozen `v1.20.0-templates/` snapshot (in `test-fixtures/0021/baselines/`). The 0021 engine now produces v1.20.0 bodies in the typecheck context, matching types.d.ts. The `types.d.ts` itself was NOT touched (0021 immutable constraint satisfied).

**Commit:** `24c13c2`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 0021/04 typecheck fixture broke after templates updated to v1.21.0**
- **Found during:** Task 3 — running full `bash migrations/run-tests.sh` after Task 2
- **Issue:** migrate-0021 (called by 0021/04/verify.sh) copies live templates. When templates became v1.21.0 (captureCheckIn bodies), the fixture's types.d.ts (which only declares `withMonitor`) caused tsc to fail.
- **Fix:** Added frozen `test-fixtures/0021/baselines/v1.20.0-templates/` (cron-monitor.ts + queue-monitor.ts at v1.20.0); updated `0021/04/verify.sh` to point `--templates-dir` at this frozen snapshot.
- **Files modified:** `migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/verify.sh`, `migrations/test-fixtures/0021/baselines/v1.20.0-templates/` (new files)
- **Constraint satisfied:** `0021/04/types.d.ts` NOT in `git diff --name-only` (immutable)
- **Commit:** `24c13c2`

**2. [Rule 2 - Missing functionality] No package.json in template directories for vitest**
- **Found during:** Task 1 setup — `npx vitest run` requires a package.json
- **Fix:** Created `package.json` in `templates/ts-cloudflare-worker/` and `templates/ts-cloudflare-pages/` with vitest 3.2.4, @sentry/cloudflare, @sentry/core devDependencies
- **Files modified:** `templates/ts-cloudflare-worker/package.json`, `templates/ts-cloudflare-pages/package.json` (+ lockfiles)
- **Commit:** `c6f162c`

**3. [Rule 2 - Missing functionality] supabase-edge cron-monitor needed flush test seam**
- **Found during:** Task 2 — the Deno stack uses test seams (not vi.mock). Added `_setFlushForTest` alongside the existing `_setCaptureCheckInForTest` so Deno tests can verify the immediate flush call.
- **Files modified:** `templates/ts-supabase-edge/cron-monitor.ts`
- **Commit:** `eaa1254`

## Obs Repository State

Branch: `split-02-rename-and-0022` (local, NOT pushed)

Recent commits:
```
24c13c2 feat(29-04): migration 0022 (1.20.0->1.21.0) + engine + fixtures + ADR-0036 (#61 in 0022 fixtures)
eaa1254 feat(29-04): explicit per-checkin flush in cron-monitor + queue-monitor (FX-SIGNALS-WORKERS-6)
c6f162c test(29-04): rewrite cron + queue monitor tests to captureCheckIn+flush contract + immediate-flush regression
a736fc2 feat(29-03): add migrations/run-tests.sh shim + MIGRATIONS_VERSION + repoint engine paths
```

## Known Stubs

None — all deliverables are wired and GREEN.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| (none) | — | All mitigations from plan threat register applied: no /Users/ paths in migrate-0022.sh; no eval of user content; FXSA marker checked via grep -q; 0021/04 types.d.ts NOT modified; 0022 to_version 1.21.0 (consumer axis, no downgrade); fixtures run in tmpdir |

## Self-Check

| Claim | Check |
|-------|-------|
| cron-monitor.test.ts has captureCheckIn mock (worker) | grep captureCheckIn templates/ts-cloudflare-worker/cron-monitor.test.ts — OK |
| queue-monitor.test.ts has captureCheckIn mock (worker) | grep captureCheckIn templates/ts-cloudflare-worker/queue-monitor.test.ts — OK |
| cron-monitor.test.ts has captureCheckIn mock (pages) | grep captureCheckIn templates/ts-cloudflare-pages/cron-monitor.test.ts — OK |
| queue-monitor.test.ts has captureCheckIn mock (pages) | grep captureCheckIn templates/ts-cloudflare-pages/queue-monitor.test.ts — OK |
| Immediate-flush regression in cron tests (worker) | grep FX-SIGNALS-WORKERS-6 + deferred + waitUntil — OK |
| Immediate-flush regression in queue tests (worker) | grep FX-SIGNALS-WORKERS-6 + deferred + waitUntil — OK |
| ctx.waitUntil(Sentry.flush) in worker cron | grep ctx.waitUntil(Sentry.flush cron-monitor.ts — OK |
| Narrowed generic in worker cron | grep "E extends { SENTRY_DSN" cron-monitor.ts — OK |
| No handlerStarted in worker cron | grep handlerStarted — NONE |
| Sentry.flush in worker queue | grep Sentry.flush queue-monitor.ts — OK |
| Sentry.flush in pages queue | grep Sentry.flush queue-monitor.ts — OK |
| flushFn in supabase-edge cron | grep flushFn cron-monitor.ts — OK |
| to_version 1.21.0 in 0022 doc | grep to_version 0022-*.md — OK |
| from_version 1.20.0 in 0022 doc | grep from_version 0022-*.md — OK |
| MIGRATIONS_VERSION = 1.21.0 | grep "version: 1.21.0" MIGRATIONS_VERSION — OK |
| FXSA marker in migrate-0022.sh | grep FXSA-WORKERS-6 migrate-0022.sh — OK |
| captureCheckIn in 0022/04 types.d.ts | grep captureCheckIn types.d.ts — OK |
| 0021/04 types.d.ts NOT in diff | git diff --name-only | grep 0021/04/types — NONE |
| FX-SIGNALS-WORKERS-6 in ADR-0036 | grep FX-SIGNALS-WORKERS-6 0036-*.md — OK |
| supersede in ADR-0036 | grep -i supersede 0036-*.md — OK |
| No /Users/ in migrate-0022.sh | grep /Users/ migrate-0022.sh — NONE |
| Full suite PASS=42 FAIL=0 XFAIL=4 | bash migrations/run-tests.sh — CONFIRMED |
| Drift PASS (1.21.0==1.21.0) | PASS: test-migrations-version-marker-matches-latest-migration-to-version |
| RED commit exists | c6f162c — FOUND |
| GREEN commit exists | eaa1254 — FOUND |
| Task 3 commit exists | 24c13c2 — FOUND |
| Feature branch | split-02-rename-and-0022 (not main) — CONFIRMED |

## Self-Check: PASSED
