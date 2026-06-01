---
phase: 25-fix-0019-engine-and-cron-wrappers
plan: 03
subsystem: testing
tags: [sentry, crons, typescript, discriminated-union, generics, type-safety, cloudflare-worker, cloudflare-pages, supabase-edge, openrouter]

requires:
  - phase: 25-fix-0019-engine-and-cron-wrappers plan 01
    provides: ADR-0032 (CronMonitorSchedule discriminated-union + D-05 narrowing scope decision), ADR-0033, RED fixture 10 for strict-Env typecheck, frozen baselines

provides:
  - D-03 discriminated-union CronMonitorSchedule across all 4 cron-monitor.ts sites
  - D-05 narrowed withCronMonitor<E> generic on cf-worker + openrouter-monitor only
  - D-19 helper exports (buildMonitorConfig + isConfigured) on cf-worker + cf-pages + openrouter-monitor
  - D-21 byte-symmetric openrouter-monitor bundled copy (mirrors cf-worker post-edit)
  - D-16 type-level firewall tests (Pitfall 4 mitigation) across all 3 test harnesses
  - D-05 strict-Env runtime test (CallbotEnv interface, cf-worker only)
  - Gemini @ts-expect-error active-firewall verification documented

affects:
  - 25-04 (queue-monitor.ts implementation — imports buildMonitorConfig + isConfigured from cf-worker + cf-pages cron-monitor.ts via D-19 exports landed here)
  - 25-05 (engine fix — migrate-0021 + fixture 10 full-GREEN depends on queue-monitor.ts from 25-04)
  - 26-sentry-scaffold (any phase scaffolding Sentry Crons into new templates reads CronMonitorSchedule type)

tech-stack:
  added: []
  patterns:
    - "D-03 discriminated union: CronMonitorSchedule uses `type =` (not `interface`) with crontab/interval variants — interval value is number not string"
    - "D-05 access-site cast: `(env as unknown as Record<string, unknown>)[envKey]` inside resolveSlug to handle dynamic env-key lookup with narrowed generic"
    - "D-16 Pitfall-4 firewall: value-level `const _: SentryMonitorConfig['schedule'] = ourSchedule` assignment bypasses skipLibCheck — forces structural compatibility check at compile time"
    - "D-16 @ts-expect-error: gemini verification pattern — temporarily fix the asserted error, confirm TS2578 'Unused' fires, revert before commit"
    - "D-21 byte-symmetry: openrouter-monitor bundled cron-monitor.ts is exact copy of cf-worker template post-edit"

key-files:
  created: []
  modified:
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts
    - add-observability/templates/ts-cloudflare-pages/cron-monitor.ts
    - add-observability/templates/ts-supabase-edge/cron-monitor.ts
    - add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts
    - add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts
    - add-observability/templates/ts-supabase-edge/cron-monitor.test.ts

key-decisions:
  - "D-05 applies to cf-worker + openrouter-monitor ONLY — cf-pages uses <R> return-type generic (not env generic); supabase-edge has no generic at all (reads Deno.env directly)"
  - "D-19 exports apply to cf-worker + cf-pages + openrouter-monitor — supabase-edge excluded because D-07 dropped supabase-edge queue-monitor; isConfigured there has no env param"
  - "D-16 strict-Env runtime test (CallbotEnv) applies to cf-worker ONLY — scope narrowed matching D-05 applicability"
  - "MonitorConfig import for Sentry type pin uses @sentry/core (not @sentry/cloudflare) for vitest stacks; npm:@sentry/deno@^8.0.0 for supabase-edge — MonitorConfig is not re-exported from @sentry/cloudflare public API"
  - "D-21 byte-symmetry achieved by rewriting openrouter-monitor copy verbatim — applying individual edits risked divergence given the complex multi-edit set"

patterns-established:
  - "D-03 discriminated union: interval value is number not string — prevents runtime cast at Sentry boundary"
  - "D-05 access-site cast pattern for dynamic env-key lookup with narrowed generics"
  - "Pitfall-4 firewall: skipLibCheck bypass via value-level Sentry type pin in test files"

requirements-completed: [SC2, SC3, SC5, SC6, D-03, D-04, D-05, D-06, D-07, D-16, D-19, D-21]

duration: ~90min (context-resumed across compaction boundary)
completed: 2026-05-31
---

# Phase 25 Plan 03: Wave 2 — cron-monitor.ts D-03 + D-05 + D-19 + D-16 + D-21 Summary

**Discriminated-union CronMonitorSchedule landed across 4 sites, D-05 generic narrowed on cf-worker + openrouter, D-19 helper exports added for Plan 04 consumption, D-16 Pitfall-4 firewalls in all 3 test harnesses with gemini @ts-expect-error active-firewall verification**

## Performance

- **Duration:** ~90 min (resumed after context compaction)
- **Started:** 2026-05-31T (Wave 2, parallel with Plan 02)
- **Completed:** 2026-05-31
- **Tasks:** 2 of 2
- **Files modified:** 7 (4 implementation + 3 test)

## Accomplishments

- Applied D-03 discriminated-union `CronMonitorSchedule` (`type =`, not `interface`) to all 4 sites; interval.value is now `number` not `string`, eliminating the cast-at-boundary footgun
- Applied D-05 narrowed `withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>` to cf-worker + openrouter-monitor only; access-site cast `(env as unknown as Record<string, unknown>)[envKey]` placed inside resolveSlug for dynamic env-key lookup
- Added D-19 `export` keyword to `buildMonitorConfig` and `isConfigured` on cf-worker + cf-pages + openrouter-monitor, making Plan 04's `import { buildMonitorConfig, isConfigured } from './cron-monitor'` ready to compile
- Achieved D-21 byte-symmetry: openrouter-monitor bundled copy is exact replica of cf-worker post-edit (`diff -q` returns empty)
- Added D-16 type-level firewall describe blocks to all 3 test harnesses (78 tests cf-worker, 63 cf-pages, 56 supabase-edge); Pitfall-4 Sentry type-pin using `@sentry/core` `MonitorConfig['schedule']` value assignment bypasses `skipLibCheck: true`
- Performed gemini @ts-expect-error active-firewall verification for all 3 stacks: temporarily fixed error line, confirmed TS2578 "Unused '@ts-expect-error' directive" fires, reverted — proving firewall is live not silently-passing

## Task Commits

1. **Task 3.1: cron-monitor.ts D-03 + D-05 + D-19 + D-21** - `7218bbb` (feat)
2. **Task 3.2: cron-monitor.test.ts D-16 firewall + strict-Env** - `bb06ac6` (test)

## Files Created/Modified

**Task 3.1 (implementation):**

- `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts` — D-03 union + D-05 narrowed generic + access-site cast + D-19 exports; `withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>`, exported `buildMonitorConfig` + `isConfigured`
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts` — D-03 union + D-19 exports only; `withCronMonitor<R>` signature unchanged (D-05 N/A — `<R>` is return type); `isConfigured(env: Record<string, unknown>)` kept wide
- `add-observability/templates/ts-supabase-edge/cron-monitor.ts` — D-03 union only; `isConfigured()` no-param shape preserved; no new exports (D-19 N/A — supabase-edge queue-monitor dropped per D-07)
- `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` — D-21 byte-symmetric with cf-worker; same D-03 + D-05 + D-19 applied; diff empty vs cf-worker

**Task 3.2 (tests):**

- `add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts` — added D-16 describe block (4 D-03 firewall tests + 1 D-05 strict-Env `CallbotEnv` test); imports `MonitorConfig` from `@sentry/core`; net +5 tests (78 total)
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts` — added D-16 D-03 firewall block (4 tests, no D-05 strict-Env); imports `MonitorConfig` from `@sentry/core`; net +4 tests (63 total)
- `add-observability/templates/ts-supabase-edge/cron-monitor.test.ts` — added D-16 D-03 firewall block in Deno.test format (4 tests); imports `MonitorConfig` from `npm:@sentry/deno@^8.0.0`; net +4 tests (56 total)

## Per-Stack Scope Outcome

| Concern | cf-worker | cf-pages | supabase-edge | openrouter-monitor |
|---------|-----------|----------|---------------|-------------------|
| D-03 union | YES | YES | YES | YES (D-21) |
| D-05 narrow generic | YES | NO (H-3: `<R>`) | NO (no generic) | YES (D-21) |
| D-19 exports | YES | YES | NO (D-07 drop) | YES (D-21) |
| D-16 strict-Env test | YES | NO | NO | n/a |
| D-16 D-03 firewall | YES | YES | YES | n/a |

## Decisions Made

- D-05 scope narrowed to cf-worker + openrouter only: codex H-3 verified that cf-pages' `withCronMonitor<R>` uses `<R>` as return type (not env type), making D-05 structurally inapplicable; supabase-edge has no generic at all
- D-19 scope excludes supabase-edge: D-07 dropped supabase-edge queue-monitor from plan scope; supabase-edge's `isConfigured()` takes no env parameter, so there is no consumer that needs those exports
- `@sentry/core` for MonitorConfig type import: `MonitorConfig` is NOT re-exported from `@sentry/cloudflare` public API (only in `@sentry/core`); supabase-edge uses `npm:@sentry/deno@^8.0.0` matching the existing cron-monitor.ts specifier
- D-21 byte-symmetry achieved via full file rewrite: applying individual edits to the openrouter-monitor copy risked divergence given the multi-edit set; Write tool rewrite from cf-worker post-edit source confirmed by `diff -q` returning empty

## Deviations from Plan

None — plan executed exactly as written. Per-stack scope choices (D-05 cf-worker+openrouter only, D-19 cf-worker+cf-pages+openrouter only, D-16 strict-Env cf-worker only) were pre-specified in the plan based on codex H-3 review findings.

## Issues Encountered

- **MonitorConfig import discovery:** Initial implementation used `import type * as Sentry from "@sentry/cloudflare"` and referenced `Sentry.MonitorConfig["schedule"]`. Running tsc revealed `MonitorConfig` is not in `@sentry/cloudflare`'s public API surface — it lives in `@sentry/core`. Corrected to `import type { MonitorConfig as SentryMonitorConfig } from "@sentry/core"`. Supabase-edge uses `npm:@sentry/deno@^8.0.0` (same specifier as production cron-monitor.ts). This is documented in the plan's Pitfall 4 section.
- **@ts-expect-error verification (gemini suggestion):** For each of the 3 test files, the executor performed the verification cycle: temporarily changed `value: "5"` to `value: 5`, ran the harness, confirmed TS2578 "Unused '@ts-expect-error' directive" fires, reverted to `value: "5"`, re-ran and confirmed PASS. This proves the D-03 type firewall is genuinely active for all 3 stacks.

## Fixture 10 Partial-GREEN Status

The strict-Env typecheck fixture at `migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck` becomes partial-GREEN after this plan:
- `withCronMonitor<CallbotEnv>` compiles (D-05 narrowing on cf-worker template satisfies the import)
- `CronMonitorSchedule` interval variant compiles with `value: number` (D-03)
- `withQueueMonitor<CallbotEnv>` remains RED — Plan 04 ships queue-monitor.ts to resolve

## Known Stubs

None — no placeholder values, hardcoded empty returns, or unconnected data paths introduced.

## Next Phase Readiness

- Plan 04 (queue-monitor.ts) can now import `{ buildMonitorConfig, isConfigured }` from `./cron-monitor` on cf-worker and cf-pages — D-19 exports are present
- Plan 05 (engine fix + migrate-0021) depends on Plan 04's queue-monitor.ts for fixture 10 full-GREEN
- D-03 type safety landed on all Sentry Crons consumers — no cast-at-boundary footgun for interval schedules
- The `CallbotEnv` strict-Env test in cf-worker's test harness will remain GREEN as long as D-05 narrowing is preserved

## Self-Check: PASSED

- FOUND: `.planning/phases/25-fix-0019-engine-and-cron-wrappers/25-03-SUMMARY.md`
- FOUND: commit `7218bbb` (feat — Task 3.1)
- FOUND: commit `bb06ac6` (test — Task 3.2)
- FOUND: all 7 modified files

---
*Phase: 25-fix-0019-engine-and-cron-wrappers*
*Completed: 2026-05-31*
