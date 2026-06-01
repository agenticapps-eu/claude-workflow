---
phase: 25
plan: "01"
subsystem: migrations/test-fixtures + docs/decisions + add-observability/templates
tags:
  - wave-0
  - adr
  - red-fixtures
  - frozen-baselines
  - queue-monitor
  - tdd

dependency_graph:
  requires: []
  provides:
    - "ADR-0031 docs/decisions/0031-0019-engine-index-ts-anchor.md — D-01 engine anchor + codex M-2 dist-path filter rationale"
    - "ADR-0032 docs/decisions/0032-cron-monitor-generic-narrowing-cf-worker-only.md — D-05 narrowed scope with H-3 exclusion rationale"
    - "ADR-0033 docs/decisions/0033-with-queue-monitor.md — D-07 + D-02b migration 0021 re-rev"
    - "Fixtures 08/09 (RED): D-01 cf-worker + cf-pages positive cases (index.ts anchor)"
    - "Fixtures 11/12 (GREEN at commit): T-25-04 + codex M-2 negative cases"
    - "Frozen v1.19.0 baselines: ts-cloudflare-worker, ts-cloudflare-pages, ts-supabase-edge cron-monitor.ts"
    - "0021 fixtures 01/02/03/04 (RED at commit): happy-path, REFUSE, SKIP, D-18 SC5"
    - "migrations/run-tests.sh test_migration_0021 dispatcher"
    - "RED queue-monitor.test.ts × 2 (cf-worker + cf-pages only, codex H-6)"
  affects:
    - "Plans 02-05 (all depend_on 25-01 for ADRs + RED fixtures + frozen baselines)"

tech_stack:
  added: []
  patterns:
    - "Frozen baseline snapshot (codex M-1): cp live template before Plan 03 mutates it"
    - "Local types.d.ts ambient declarations (codex H-2): avoids @cloudflare/workers-types dependency in fixture typecheck"
    - "Guarded Shape A test pattern (ADR-0029 inheritance): handlerStarted flag + sync-throw test (codex M-6)"
    - "D-10 tightened canonical-phrase regex: no organic batch.queue match path"

key_files:
  created:
    - docs/decisions/0031-0019-engine-index-ts-anchor.md
    - docs/decisions/0032-cron-monitor-generic-narrowing-cf-worker-only.md
    - docs/decisions/0033-with-queue-monitor.md
    - migrations/test-fixtures/0019/08-index-ts-anchored-worker/{setup,verify}.sh
    - migrations/test-fixtures/0019/09-index-ts-anchored-pages/{setup,verify}.sh
    - migrations/test-fixtures/0019/11-stray-index-ts-no-co-anchor/{setup,verify}.sh
    - migrations/test-fixtures/0019/12-dist-shaped-anchor-pair/{setup,verify}.sh
    - migrations/test-fixtures/0021/baselines/v1.19.0/ts-cloudflare-worker/cron-monitor.ts
    - migrations/test-fixtures/0021/baselines/v1.19.0/ts-cloudflare-pages/cron-monitor.ts
    - migrations/test-fixtures/0021/baselines/v1.19.0/ts-supabase-edge/cron-monitor.ts
    - migrations/test-fixtures/0021/common-setup.sh
    - migrations/test-fixtures/0021/01-fresh-1.19.0-apply/{setup,verify}.sh
    - migrations/test-fixtures/0021/02-callbot-shape-dirty-refuse/{setup,verify}.sh
    - migrations/test-fixtures/0021/03-already-1.20.0-skip/{setup,verify}.sh
    - migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/{setup,verify,env,types.d,tsconfig}.ts/json/sh
    - add-observability/templates/ts-cloudflare-worker/queue-monitor.test.ts
    - add-observability/templates/ts-cloudflare-pages/queue-monitor.test.ts
  modified:
    - migrations/run-tests.sh (added test_migration_0021 function + FILTER dispatch entry)

decisions:
  - "OQ-8 RESOLVED (re-rev): Migration 0021 = RE-REV with dirty detection (mirrors 0019 canonicalize_awk + all-clean-gate). NOT additive-only (would leave callbot's cron-monitor.ts broken). Documented in ADR-0033 Migration delivery subsection."
  - "OQ-9 LOCKED (D-19): queue-monitor.ts imports CronMonitorConfig (type), buildMonitorConfig (value), isConfigured (value) from ./cron-monitor via single import line. cf-worker + cf-pages ONLY."
  - "OQ-10 DROPPED: supabase-edge queue-monitor.ts dropped per D-07 revised scope (codex H-6: Deno runtime, no Cloudflare Queue equivalent)."
  - "OQ-11: Migration 0021 docs = standalone spec mirroring 0019.md section structure (Plan 05 delivers)."
  - "Codex revisions folded: H-1 (D-18 migrated-wrapper under 0021/04), H-2 (local types.d.ts), H-3 (cf-pages/supabase-edge excluded from D-05), H-6 (supabase-edge queue-monitor dropped), H-7 (re-rev rationale in ADR-0033), M-1 (frozen baselines), M-2 (fixture 12), M-6 (sync-throw test), M-8 (twofold idempotency fixture 03), M-9 (REFUSE fixture 02)."

metrics:
  duration_minutes: 9
  completed_date: "2026-05-31"
  tasks_completed: 4
  tasks_total: 4
  files_created: 38
  files_modified: 1
---

# Phase 25 Plan 01: Wave 0 ADRs + RED fixtures + frozen v1.19.0 baselines + RED queue-monitor tests Summary

**One-liner:** Three Accepted ADRs (engine anchor D-01, generic narrowing D-05 cf-worker-only, withQueueMonitor D-07 re-rev 0021) + twelve RED test fixtures (08/09/11/12 for 0019; 01/02/03/04 for 0021) + frozen v1.19.0 cron-monitor.ts baselines (codex M-1) + RED queue-monitor.test.ts × 2 stacks (11 cases each, codex M-6 sync-throw).

## Tasks Completed

| Task | Name | Commit | Key Deliverables |
|------|------|--------|------------------|
| 1.1 | ADRs 0031/0032/0033 | baee309 | docs/decisions/0031, 0032, 0033 — all Status: Accepted |
| 1.2 | RED 0019 fixtures 08/09/11/12 | 376be51 | D-01 positive (08/09), T-25-04 negative (11), codex M-2 negative (12) |
| 1.3 | Frozen baselines + 0021 fixtures + dispatcher | daed7d6 | 3× v1.19.0 baselines; 0021/01-04; common-setup.sh; test_migration_0021 in run-tests.sh |
| 1.4 | RED queue-monitor.test.ts × 2 | 0747bf0 | cf-worker + cf-pages only; 11 tests each; codex M-6 sync-throw; D-10 tightened regex |

## RED State at Commit (Intentional)

Per plan spec — Plan 01 is Wave 0 foundation. All fixtures are intentionally RED at commit time:

- **Fixtures 08/09** (D-01 cf-worker + cf-pages positive): FAIL — engine still looks for `lib-observability.ts` only; Plan 02 fixes engine.
- **Fixture 11** (stray index.ts negative): PASSES at commit (engine never looked for stray index.ts anyway — regression insurance for Plan 02's widened find).
- **Fixture 12** (dist-shaped pair negative): PASSES at commit (engine doesn't yet look for index.ts under dist/ — actively tests Plan 02's codex M-2 dist-path filter after that lands).
- **0021 fixtures 01/02/03/04**: SKIP (no engine yet — Plan 05 ships `migrate-0021-with-cron-and-queue-updates.sh`).
- **queue-monitor.test.ts × 2**: FAIL with "Cannot find module './queue-monitor'" — Plan 04 ships the implementation.

GREEN plan per fixture:
- Plan 02: 0019 fixtures 08/09/11/12 turn GREEN (engine + dist-path filter)
- Plan 03: 0021/04 partially GREEN (cron-monitor.ts compiles; queue-monitor still missing)
- Plan 04: queue-monitor.test.ts × 2 GREEN; 0021/04 fully GREEN end-to-end
- Plan 05: 0021 fixtures 01/02/03 GREEN (engine ships); 0019 fixtures 08/09 fully GREEN (D-11 queue-monitor.ts copy step)

## OQ Resolutions (Locked for Downstream Plans)

- **OQ-8 [RESOLVED iter-2]:** Migration 0021 = re-rev with dirty detection (mirrors 0019 canonicalize_awk). NOT additive-only. ADR-0033 Migration delivery subsection documents the H-7 rationale.
- **OQ-9 [LOCKED iter-2-c → D-19]:** `queue-monitor.ts` re-imports `CronMonitorConfig` (type), `buildMonitorConfig` (value), `isConfigured` (value) from `./cron-monitor` via single import line. cf-worker + cf-pages ONLY. Plans 03/04 implement.
- **OQ-10 [DROPPED iter-2]:** N/A — supabase-edge queue-monitor dropped (codex H-6, D-07 narrowed).
- **OQ-11:** Migration 0021 docs = standalone spec mirroring 0019.md (Plan 05 delivers).

## Codex Revisions Folded

| Codex ref | What it mandated | Where applied |
|-----------|-----------------|---------------|
| H-1 | D-18 → migrated-wrapper fixture (not template-import) | 0021/04 shape |
| H-2 | Local types.d.ts, no @cloudflare/workers-types dependency | 0021/04/types.d.ts |
| H-3 | cf-pages + supabase-edge excluded from D-05 generic narrowing | ADR-0032 exclusion paragraph |
| H-6 | Drop ts-supabase-edge queue-monitor.test.ts (Deno, no Queue equivalent) | No supabase-edge file created |
| H-7 | Re-rev rationale: additive-only 0021 fails to close findings 2+3 for v1.19.0 | ADR-0033 Migration delivery + OQ-8 resolution |
| M-1 | Frozen literal files for 0021 fixtures (not cp from mutable templates) | baselines/v1.19.0/ + common-setup.sh |
| M-2 | dist/build/out path negative filter even with both anchors present | Fixture 12 setup.sh + verify.sh |
| M-6 | Explicit sync-throw test (not just async rejection) | queue-monitor.test.ts `SYNCHRONOUSLY` test |
| M-8 | Twofold idempotency: BOTH queue-monitor.ts present AND cron-monitor.ts hash matches v1.20.0 | Fixture 03 mtime-invariance verify.sh |
| M-9 | REFUSE-on-dirty: callbot LOCAL-PATCH appended to cron-monitor.ts triggers refuse | Fixture 02 setup.sh + verify.sh |

## Deviations from Plan

None — plan executed exactly as written. The ADRs, fixtures, baselines, and test stubs all follow the plan spec verbatim. No Rule 1/2/3 interventions were needed.

## Known Stubs

None — this plan creates infrastructure (ADRs, test fixtures, frozen baselines, RED test stubs) that are intentionally incomplete by design. The RED state is documented above and is the correct output for Wave 0.

## Self-Check: PASSED
