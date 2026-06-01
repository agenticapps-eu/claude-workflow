---
phase: 25-fix-0019-engine-and-cron-wrappers
verified: 2026-06-01T00:00:00Z
status: passed
score: 7/7 must-haves verified
goal_achieved: true
overrides_applied: 0
re_verification: false
---

# Phase 25: Fix 0019 Engine + withCronMonitor — Verification Report

**Phase Goal:** Close the four discrete gaps surfaced by GitHub issue #56 when migrating callbot v1.16.0 → v1.19.0 (engine misses index.ts wrappers; CronMonitorSchedule incompatible with Sentry's discriminated union; withCronMonitor generic clashes with strict Env; ship withQueueMonitor).
**Verified:** 2026-06-01
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Scope Narrowings (by design — NOT gaps)

Per codex review revisions honored in all plans:
- **D-05 (generic narrowing):** Applies to `ts-cloudflare-worker` + `openrouter-monitor` bundled ONLY. cf-pages uses `<R>` return-type generic (not env generic, codex H-3 verified). supabase-edge has no generic.
- **D-07 (withQueueMonitor scope):** Applies to `ts-cloudflare-worker` + `ts-cloudflare-pages` ONLY. No `ts-supabase-edge/queue-monitor.ts` (codex H-6: Deno runtime, no Cloudflare Queue equivalent).
- **D-19 (helper exports):** `buildMonitorConfig` + `isConfigured` exported from cf-worker + cf-pages + openrouter-monitor. NOT supabase-edge (no queue-monitor consumer there).
- **Migration 0021:** RE-REV with dirty detection (not additive-only), per codex H-7.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | Migration 0019 engine accepts `index.ts`-anchored wrappers with sibling co-anchor | VERIFIED | `_filter_index_ts_requires_co_anchor` helper present in engine; `-name index.ts` in find candidate set; classify_stack accepts `index.ts OR lib-observability.ts`; fixtures 08 + 09 PASS; `bash migrations/run-tests.sh 0019` → 12/12 PASS |
| SC2 | `CronMonitorSchedule` matches Sentry's `MonitorSchedule` discriminated union; interval schedule compiles without casts | VERIFIED | `type CronMonitorSchedule` (not interface) with `{ type: 'crontab'; value: string } \| { type: 'interval'; value: number; unit: ... }` present in all 4 sites; D-16 type-level firewall in test harnesses; template tests pass |
| SC3 | `withCronMonitor` works with strict-typed `Env` interfaces on cf-worker + openrouter (narrowed scope, by design) | VERIFIED | `E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }` in cf-worker/openrouter; access-site cast `(env as unknown as Record<string, unknown>)[envKey]`; `withCronMonitor<CallbotEnv>` test in cron-monitor.test.ts passes; fixture 0021/04 tsc exits 0 |
| SC4 | `withQueueMonitor` exists with Guarded Shape A semantics for cf-worker + cf-pages (narrowed scope, by design) | VERIFIED | Both `ts-cloudflare-worker/queue-monitor.ts` and `ts-cloudflare-pages/queue-monitor.ts` exist; `handlerStarted` flag present; Guarded Shape A pattern verbatim; 11 tests pass per stack (22 total); codex M-6 sync-throw test GREEN |
| SC5 | Fixture 0021/04 (callbot-shape strict-Env typecheck) runs 0021 engine + `tsc --noEmit` exits 0 | VERIFIED | `bash migrations/run-tests.sh 0021` → fixture 04 PASS; "fixture 0021/04 OK — D-18 SC5 GREEN (migrated wrapper compiles with strict CallbotEnv; codex M-7 end-to-end)" |
| SC6 | Test surface extended — fixtures 08/09/11/12 (0019), fixtures 01-04 (0021), type-level firewall × 3 stacks, queue-monitor.test.ts × 2 | VERIFIED | 0019 suite: 12/12 PASS (08/09/11/12 included); 0021 suite: 4/4 PASS; D-16 firewall in all 3 test harnesses; 22 new queue-monitor.test.ts assertions GREEN; cf-worker: 89 tests, cf-pages: 74 tests, supabase-edge: 56 tests |
| SC7 | Issue #56 has 4 linkback comments — one per finding | VERIFIED | `gh issue view 56 --comments \| grep -c "Phase 25"` returns 4; comments confirm F1/F2/F3/F4 all resolved with narrowed-scope callouts |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `docs/decisions/0031-0019-engine-index-ts-anchor.md` | Status: Accepted, D-01 + codex M-2 dist-path filter | VERIFIED | Status: Accepted; Context/Decision/Alternatives Rejected/Consequences sections present; codex M-2 dist-path rationale included |
| `docs/decisions/0032-cron-monitor-generic-narrowing-cf-worker-only.md` | Status: Accepted, D-05 narrowed scope + H-3 exclusion rationale | VERIFIED | Status: Accepted; cf-pages/supabase-edge exclusion paragraph present; SENTRY_DSN constraint documented |
| `docs/decisions/0033-with-queue-monitor.md` | Status: Accepted, D-07 + D-02b re-rev rationale | VERIFIED | Status: Accepted; Migration delivery subsection; Guarded Shape A (ADR-0029); re-rev rationale; codex H-7 |
| `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` | `_filter_index_ts_requires_co_anchor` + `resolve_anchor_files` + dist-path filter + queue-monitor.ts copy in apply_root | VERIFIED | All four elements present; fixtures 08/09/11/12 pass |
| `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts` | discriminated-union CronMonitorSchedule + narrowed E generic + exported buildMonitorConfig/isConfigured | VERIFIED | `type CronMonitorSchedule`; `E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }`; `export function buildMonitorConfig`; `export function isConfigured` |
| `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts` | D-03 + D-19 only (no D-05 — `<R>` return-type generic) | VERIFIED | `type CronMonitorSchedule`; `export function buildMonitorConfig`; `export function isConfigured`; withCronMonitor signature is `<R>` not `<E>` (D-05 correctly absent) |
| `add-observability/templates/ts-supabase-edge/cron-monitor.ts` | D-03 only — no D-05, no D-19 | VERIFIED | `type CronMonitorSchedule`; no `export function buildMonitorConfig` (D-19 correctly absent); no narrowed generic |
| `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` | D-21 byte-symmetric with cf-worker | VERIFIED | `diff -q` returns empty — byte-identical to cf-worker |
| `add-observability/templates/ts-cloudflare-worker/queue-monitor.ts` | withQueueMonitor + Guarded Shape A + D-19 import + D-10 phrase | VERIFIED | All elements present; D-10 canonical phrase `MUST pass explicit monitorSlug`; single-line D-19 import from ./cron-monitor |
| `add-observability/templates/ts-cloudflare-pages/queue-monitor.ts` | Byte-identical to cf-worker queue-monitor.ts | VERIFIED | `diff -q` returns empty — byte-identical to cf-worker variant |
| `add-observability/templates/ts-supabase-edge/queue-monitor.ts` | MUST NOT EXIST (codex H-6) | VERIFIED | File absent; confirmed by `test ! -e` |
| `templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh` | Re-rev engine with canonicalize_awk + all-clean-gate | VERIFIED | File exists; `canonicalize_awk` mirror present; all 4 fixtures PASS |
| `migrations/0021-with-cron-and-queue-updates.md` | from_version 1.19.0 → to_version 1.20.0, RE-REV with dirty detection | VERIFIED | `from_version: 1.19.0`; `to_version: 1.20.0`; twofold idempotency; REFUSE path documented |
| `migrations/0019-sentry-crons-and-healthz.md` | D-02a re-rev note + Recovery section + Files Copied update | VERIFIED | "Re-rev 2026-05-31" note present; `## Recovery` section references Migration 0021; queue-monitor.ts in Files Copied with supabase-edge carve-out |
| `migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/verify.sh` | Runs 0021 engine + tsc --noEmit against strict CallbotEnv | VERIFIED | Fixture passes as part of 0021 suite; "D-18 SC5 GREEN" confirmation in test output |
| `migrations/test-fixtures/0021/baselines/v1.19.0/*/cron-monitor.ts` | Frozen v1.19.0 baselines for 3 stacks (codex M-1) | VERIFIED | All 3 baseline files exist |
| `skill/SKILL.md` | version: 1.20.0 | VERIFIED | `grep -q "version: 1.20.0" skill/SKILL.md` |
| `add-observability/SKILL.md` | version: 0.9.0 | VERIFIED | `grep -q "version: 0.9.0" add-observability/SKILL.md` |
| `CHANGELOG.md` | [1.20.0] entry | VERIFIED | Entry present with Added/Fixed/Notes sections covering all Phase 25 deliverables |
| `add-observability/CHANGELOG.md` | 0.9.0 entry | VERIFIED | Entry present |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| Engine find candidates | `_filter_index_ts_requires_co_anchor` | pipe filter | WIRED | `-name index.ts \| _filter_index_ts_requires_co_anchor \| sort -u` confirmed in engine |
| `classify_stack` (cf-worker/cf-pages) | `index.ts OR lib-observability.ts` dual-anchor | conditional branch | WIRED | Both anchor filenames accepted; existing fixtures unchanged |
| `resolve_anchor_files` | `is_known_clean_wrapper` + `emit_refuse_artifacts_for` | function calls | WIRED | >= 3 occurrences of `resolve_anchor_files` in engine (confirmed by SUMMARY: 7 occurrences) |
| `apply_root` (cf-worker/cf-pages) | `queue-monitor.ts` copy step | `cp "$qm" "$dir/queue-monitor.ts"` | WIRED | D-11 split branch confirmed in engine; fixtures 08/09 PASS |
| `queue-monitor.ts` imports | `cron-monitor.ts` exports | `import { type CronMonitorConfig, buildMonitorConfig, isConfigured }` | WIRED | D-19 single-line re-import confirmed in both cf-worker + cf-pages queue-monitor.ts; no inline duplication |
| Migration 0021 engine | frozen v1.19.0 baselines | `BASELINES_DIR` → `migrations/test-fixtures/0021/baselines/v1.19.0/` | WIRED | Engine points to frozen literal files (codex M-1); confirmed by SUMMARY decisions |
| Migration 0021 fixtures | test dispatcher | `test_migration_0021()` in `run-tests.sh` | WIRED | 4/4 fixtures PASS under `bash migrations/run-tests.sh 0021` |

### Data-Flow Trace (Level 4)

Not applicable for this phase — deliverables are bash engine scripts, TypeScript template wrappers, and migration fixtures. No React/UI components rendering dynamic data. The functional data flows (engine writes to wrapper dirs; queue-monitor fetches env DSN; fixture tsc checks type safety) are all verified through the behavioral test suite (189/189 migration tests PASS; all template harnesses PASS).

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Migration 0019 suite (12 fixtures including 08/09/11/12) | `bash migrations/run-tests.sh 0019` | 12 PASS, 0 FAIL | PASS |
| Migration 0021 suite (4 fixtures: fresh-apply, dirty-refuse, skip, SC5-typecheck) | `bash migrations/run-tests.sh 0021` | 4 PASS, 0 FAIL | PASS |
| Full migration suite | `bash migrations/run-tests.sh` | 189 PASS, 0 FAIL | PASS |
| Template test suite (all stacks) | `bash add-observability/templates/run-template-tests.sh all` | All stacks PASS | PASS |
| Issue #56 linkback comments | `gh issue view 56 --comments \| grep -c "Phase 25"` | 4 | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SC1 | Plans 01, 02, 05 | Engine accepts index.ts-anchored wrappers | SATISFIED | Fixture 08/09/11/12 PASS; filter + classify + resolve_anchor_files all present |
| SC2 | Plans 01, 03 | CronMonitorSchedule discriminated union | SATISFIED | `type CronMonitorSchedule` in all 4 sites; D-16 firewall tests pass |
| SC3 | Plans 01, 03 | withCronMonitor strict-Env (cf-worker + openrouter, narrowed scope) | SATISFIED | Narrowed generic present; fixture 0021/04 tsc exits 0 |
| SC4 | Plans 01, 04 | withQueueMonitor Guarded Shape A (cf-worker + cf-pages, narrowed scope) | SATISFIED | Both queue-monitor.ts files exist; 22 test assertions GREEN |
| SC5 | Plans 01, 04, 05 | SC5 strict-Env typecheck fixture GREEN | SATISFIED | fixture 0021/04 PASS with tsc --noEmit |
| SC6 | Plans 01-05 | Test surface extended | SATISFIED | 12/12 0019 fixtures; 4/4 0021 fixtures; 22 queue-monitor assertions; D-16 firewall in 3 test harnesses |
| SC7 | Plan 05 | Issue #56 4 linkback comments | SATISFIED | `gh issue view 56 --comments` returns 4 Phase 25 comments (F1/F2/F3/F4) |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh` | ~601-604 | `local_dir`/`local_stack` loop variables named as if `local` but are script-global (WR-01) | Warning | Future refactoring risk only; current code correct; identified in code review |
| `templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh` | ~547-554 | `apply_root_021` returns 0 for go-fly-http — pass-1 guard is the only protection (WR-02) | Warning | Unreachable in practice; go-fly-http filtered at pass-1; no test fixture covers the guard path |
| `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts` | ~58-63 | `isConfigured` signature asymmetry with cf-worker (`Record<string, unknown>` vs `{ SENTRY_DSN?: string }`) — WR-03 intentional | Warning | Annotated as intentional at cron-monitor.ts line 58: "WR-03 (Phase 25 code review) — signature ASYMMETRY with cf-worker is intentional"; template tests pass; TypeScript accepts the call due to structural subtyping |
| `add-observability/templates/run-template-tests.sh` | ~208,231 | `trap - EXIT` clears the harness-level EXIT trap (WR-04) | Warning | Minor: cleanup-on-kill edge case only; tests pass correctly |

All four REVIEW warnings:
- WR-01/WR-02: Non-blocking future maintenance concerns identified in code review; do not affect correctness of current migration behavior.
- WR-03: Explicitly documented as intentional deviation in source code at cron-monitor.ts:58; template tests (74 tests) pass without issue.
- WR-04: Trap cleanup edge case; does not affect test results.

No blockers. No stubs or placeholder implementations found.

### Human Verification Required

None. All success criteria are verifiable programmatically:
- Migration engine behavior verified via fixture test suite (189/189 PASS).
- Type safety verified via tsc --noEmit in fixture 0021/04 (PASS).
- Issue linkbacks verified via gh CLI (4 Phase 25 comments confirmed).
- Template test suite fully automated (all stacks PASS).

### Gaps Summary

No gaps found. All 7 success criteria are met:

1. **SC1** — Migration 0019 engine accepts `index.ts`-anchored wrappers. The fix is complete: find candidate widening, pre-classify filter (co-anchor + dist-path), dual-anchor classify_stack, resolve_anchor_files helper, and D-11 apply_root extension for queue-monitor.ts. Fixtures 08/09/11/12 all PASS.

2. **SC2** — `CronMonitorSchedule` is now a discriminated union compatible with Sentry's `MonitorSchedule`. Applied to all 4 TS sites. D-16 type-level firewalls active in all 3 test harnesses.

3. **SC3** — `withCronMonitor` generic narrowed on cf-worker + openrouter-monitor (by design per codex H-3; cf-pages uses `<R>` return-type generic; supabase-edge has no generic). SC5 fixture confirms callbot-shape Env compiles without casts.

4. **SC4** — `withQueueMonitor` ships on cf-worker + cf-pages with full Guarded Shape A semantics. 22 test assertions GREEN. supabase-edge correctly absent (codex H-6).

5. **SC5** — Fixture 0021/04 runs the full 0021 engine against a v1.19.0 seeded wrapper and verifies tsc --noEmit exits 0 with a strict CallbotEnv interface. PASS.

6. **SC6** — Test surface extended with 12 new migration fixtures (0019: 08/09/11/12; 0021: 01/02/03/04), D-16 type firewalls in 3 stacks, and 22 new queue-monitor assertions.

7. **SC7** — 4 linkback comments on issue #56 confirmed via gh CLI.

---

_Verified: 2026-06-01_
_Verifier: Claude (gsd-verifier)_
