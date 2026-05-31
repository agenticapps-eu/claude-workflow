---
phase: 25
plan: "04"
subsystem: add-observability/templates
tags:
  - wave-3
  - queue-monitor
  - tdd
  - guarded-shape-a
  - cloudflare-worker
  - cloudflare-pages
  - d19-import-contract

dependency_graph:
  requires:
    - "25-01 (RED queue-monitor.test.ts x2 + D-19 contract locked)"
    - "25-03 (cron-monitor.ts exports buildMonitorConfig + isConfigured for D-19 re-import)"
  provides:
    - "add-observability/templates/ts-cloudflare-worker/queue-monitor.ts — withQueueMonitor (D-07/D-08/D-09/D-10/D-19)"
    - "add-observability/templates/ts-cloudflare-pages/queue-monitor.ts — byte-identical to cf-worker"
    - "run-template-tests.sh queue-monitor.{ts,test.ts} wirings for cf-worker + cf-pages"
    - "queue-monitor.test.ts x2 GREEN (22 assertions: 11 per stack)"
  affects:
    - "25-05 (engine apply_root extension for D-11 queue-monitor.ts copy; fixture 0021/04 full-GREEN)"

tech_stack:
  added: []
  patterns:
    - "D-19 re-import contract: queue-monitor.ts imports {type CronMonitorConfig, buildMonitorConfig, isConfigured} from ./cron-monitor (single line; no inline duplication)"
    - "Guarded Shape A (ADR-0029 D-08): handlerStarted flag distinguishes pre-callback transport fail (unmonitored fallback) from post-callback errors (propagate)"
    - "Codex M-6 sync-throw correctness: sync throw inside withMonitor callback bubbles through with handlerStarted=true; wrapper re-throws correctly"
    - "D-09 3-source slug resolution: explicit > SENTRY_CRON_MONITOR_SLUG_QUEUE env > auto-derive ${SERVICE_NAME}:queue:${batch.queue}"
    - "D-10 silent+docs multi-queue policy: canonical phrase 'MUST pass explicit monitorSlug' in jsdoc anchors D-10 regex assertion"
    - "Codex H-6 supabase-edge drop: no ts-supabase-edge/queue-monitor.ts (Deno runtime, no Cloudflare Queue equivalent)"
    - "Byte-symmetry: cf-worker and cf-pages queue-monitor.ts are byte-identical"

key_files:
  created:
    - add-observability/templates/ts-cloudflare-worker/queue-monitor.ts
    - add-observability/templates/ts-cloudflare-pages/queue-monitor.ts
  modified:
    - add-observability/templates/run-template-tests.sh

decisions:
  - "D-19 honored via single-line import from ./cron-monitor: no inline duplication of buildMonitorConfig or isConfigured; Plan 03's exports are consumed here"
  - "Codex H-6 drop confirmed: ts-supabase-edge/queue-monitor.ts NOT created (Deno runtime, MessageBatch + ExecutionContext are Workers-runtime types)"
  - "Codex M-6 sync-throw: standard Guarded Shape A pattern handles this correctly out of the box — sync throw inside withMonitor callback sets handlerStarted=true and bubbles through to catch which re-throws"
  - "SC5 / fixture 0021/04 remains SKIP: engine migrate-0021 not yet present (Plan 05); the tsc check through the full fixture runner requires the engine"
  - "Fixtures 08/09 partial-GREEN maintained: queue-monitor.ts install assertion still fails in verify.sh because Plan 05 has not extended apply_root yet — documented caveat"

metrics:
  duration_minutes: 5
  completed_date: "2026-05-31"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 1
---

# Phase 25 Plan 04: Wave 3 — queue-monitor.ts x2 stacks + harness wiring Summary

**One-liner:** withQueueMonitor with Guarded Shape A + D-19 re-import from ./cron-monitor landed on cf-worker + cf-pages (22 new GREEN tests); run-template-tests.sh wired for queue-monitor; supabase-edge explicitly absent per codex H-6.

## Tasks Completed

| Task | Name | Commit | Key Deliverables |
|------|------|--------|------------------|
| 4.1 | queue-monitor.ts x2 TS stacks (D-07/D-08/D-09/D-10/D-19 + M-6) | 6eb36c1 | cf-worker + cf-pages queue-monitor.ts; byte-identical; Guarded Shape A; D-19 import; M-6 sync-throw |
| 4.2 | Wire queue-monitor into run-template-tests.sh harness x2 stacks | 81d2091 | +4 substitute_tokens lines; cf-worker 78→89, cf-pages 63→74 tests |

## Implementation Details

### Task 4.1 — queue-monitor.ts

Both `add-observability/templates/ts-cloudflare-worker/queue-monitor.ts` and the byte-identical cf-pages copy implement:

- **D-07 signature:** `withQueueMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }, Msg = unknown>(handler: (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => void | Promise<void>, config?: CronMonitorConfig): (batch: ...) => Promise<void>`
- **D-08 Guarded Shape A:** `handlerStarted` flag; pre-callback Sentry transport throw → unmonitored fallback (queue always runs); post-callback errors propagate
- **D-09 resolveQueueSlug:** explicit config.monitorSlug > SENTRY_CRON_MONITOR_SLUG_QUEUE env > `${SERVICE_NAME ?? "service"}:queue:${batch.queue}`
- **D-10 multi-queue policy:** canonical phrase "MUST pass explicit monitorSlug" in jsdoc; anchors D-10 regex assertion in test file
- **D-19 import contract:** `import { type CronMonitorConfig, buildMonitorConfig, isConfigured } from "./cron-monitor"` — single line, no inline duplication; Plan 03's exports consumed here
- **Codex M-6:** sync throw inside withMonitor callback sets handlerStarted=true before throwing, then bubbles through to catch which re-throws (post-callback path); working correctly out of the box with standard Guarded Shape A pattern
- **Codex H-6:** NO ts-supabase-edge/queue-monitor.ts created

### Task 4.2 — run-template-tests.sh

Added 4 lines total (2 per stack block):
- `substitute_tokens "$SRC/queue-monitor.ts" "$OBS_DIR/queue-monitor.ts"`
- `substitute_tokens "$SRC/queue-monitor.test.ts" "$OBS_DIR/queue-monitor.test.ts"`

Applied to `run_ts_cloudflare_worker` and `run_ts_cloudflare_pages` blocks. No changes to `run_ts_supabase_edge` block (codex H-6 — no queue-monitor.ts there).

## Test Results

| Stack | Before | After | Delta |
|-------|--------|-------|-------|
| cf-worker | 78 passed | 89 passed | +11 (queue-monitor.test.ts) |
| cf-pages | 63 passed | 74 passed | +11 (queue-monitor.test.ts) |
| supabase-edge | 56 passed | 56 passed | 0 (unchanged) |

All 11 assertions per stack GREEN:
- Guarded Shape A happy path (withMonitor called once with slug + monitorConfig)
- Async handler rejection propagates
- **Codex M-6 NEW:** Sync throw post-callback → wrapper re-throws (not fallback)
- No-op when SENTRY_DSN unset (R02 fail-safe)
- Pre-callback transport throw → unmonitored fallback
- Post-callback transport throw → propagates
- Slug resolution: explicit wins
- Slug resolution: SENTRY_CRON_MONITOR_SLUG_QUEUE env wins
- Slug resolution: auto-derive ${SERVICE_NAME}:queue:${batch.queue}
- Slug resolution: auto-derive defaults SERVICE_NAME to "service"
- D-10 canonical-phrase doc-comment regex assertion

## Open Work for Plan 05

- **D-11 engine extension:** `apply_root()` in `migrate-0019-sentry-crons-and-healthz.sh` must copy `queue-monitor.ts` for cf-worker + cf-pages (narrowed per D-07). Until this lands, fixtures 08/09 remain partial-GREEN (verify.sh `queue-monitor.ts not installed` assertion fails).
- **SC5 / Fixture 0021/04:** The strict-Env typecheck fixture's verify.sh runs migrate-0021 which Plan 05 ships. Once the engine exists, fixture 04 will run the full tsc check (codex M-7 end-to-end import-contract enforcement).
- **D-02b / migrate-0021:** Full re-rev engine with dirty detection; delivers updated cron-monitor.ts + new queue-monitor.ts to v1.19.0 consumers.
- **D-02a / 0019.md docs amendment** and **D-11 queue-monitor section** in migration docs.
- **D-13/D-14 version bumps** (add-observability 0.9.0; claude-workflow 1.20.0).

## Success Criteria Satisfied

- **SC4** (withQueueMonitor Guarded Shape A): GREEN — cf-worker + cf-pages
- **SC6** (test surface extended): +22 cases (11 per stack × 2 stacks; codex M-6 sync-throw included)
- **D-07** (new queue-monitor.ts cf-worker + cf-pages, no supabase-edge): satisfied
- **D-08** (Guarded Shape A): satisfied; handlerStarted pattern verbatim from cron-monitor.ts lines 119-152
- **D-09** (3-source slug resolution): satisfied; auto-derive uses batch.queue
- **D-10** (multi-queue docs policy): satisfied; canonical phrase in jsdoc
- **D-17** (queue-monitor.test.ts x2): RED → GREEN; 22 assertions
- **D-19** (helper export contract): satisfied; single-line re-import; no inline duplication
- **Codex H-6** (supabase-edge drop): confirmed absent
- **Codex M-6** (sync-throw test): GREEN

## Deviations from Plan

None — plan executed exactly as written. The two tasks follow the prescribed TDD sequence (RED confirmed by file absence, impl written, harness wired, GREEN confirmed). Task 4.2 was implemented immediately after 4.1 since the harness wiring is required to exercise the tests. The plan anticipated this ordering (Task 4.2 `depends_on: Task 4.1`).

## Known Stubs

None — withQueueMonitor is fully implemented; no placeholder values or unconnected paths. The SC5/fixture-04 SKIP is a deliberate gate on Plan 05's engine, not a stub in this plan's deliverables.

## Threat Surface Scan

No new security-relevant surface beyond what the plan's threat_model covered:
- `batch.queue` flows into auto-derived slug (T-25-02: accepted, LOW)
- Guarded Shape A unmonitored fallback (T-25-03: accepted, LOW per ADR-0029)
- SENTRY_CRON_MONITOR_SLUG_QUEUE operator env var (T-25-08: accepted, LOW)

No new endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check: PASSED

- FOUND: `add-observability/templates/ts-cloudflare-worker/queue-monitor.ts`
- FOUND: `add-observability/templates/ts-cloudflare-pages/queue-monitor.ts`
- CONFIRMED ABSENT: `add-observability/templates/ts-supabase-edge/queue-monitor.ts`
- FOUND: commit `6eb36c1` (feat — Task 4.1)
- FOUND: commit `81d2091` (test — Task 4.2)
- VERIFIED: byte-identical (diff empty)
- VERIFIED: D-19 import line present in both files
- VERIFIED: no inline buildMonitorConfig/isConfigured in either file
- VERIFIED: 89 tests GREEN (cf-worker), 74 tests GREEN (cf-pages), 56 tests GREEN (supabase-edge)

---
*Phase: 25-fix-0019-engine-and-cron-wrappers*
*Completed: 2026-05-31*
