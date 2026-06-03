# Roadmap: claude-workflow

> **Status: minimum stub.** This ROADMAP.md was created on 2026-05-31 as a single-phase
> enabler so `/gsd-discuss-phase 25` could proceed. A full retroactive bootstrap of
> Phases 01-24 (and STATE.md / PROJECT.md) remains deferred — that work is its own future
> phase. Until then, treat phases 01-24's status as "shipped — see git history" and consult
> the per-phase directories under `.planning/phases/` for artefacts.
>
> Phase 24 (PR #55) was the last shipped phase, at commit `875c90c`, claude-workflow
> v1.19.0 / add-observability v0.8.0. Phase 25 is the first phase tracked formally here.

## Milestones

- ✅ **v0.x → v1.19.0** — Phases 01-24 (shipped, see `session-handoff.md` and git log; not enumerated here)
- ✅ **v1.20.x worker-template hardening + 0019 engine fixes** — Phases 25-26 (shipped 1.20.0; PR #60 merged `46bb394`)
- ✅ **v1.21.0 stable baseline (SPLIT-00 gate)** — Phase 27 (shipped + merged PR #62 `5aff1b1`; release/baseline tag `v1.21.0`; skill version stays 1.20.0 — tag-only, no migration). All three factiv downstreams recorded on the 1.21.0 baseline (DOWNSTREAM-EVIDENCE RULE).
- ✅ **repo-split (claude-workflow v2.0.0)** — Phases 28-30 (shipped 2026-06-03; PR #68, tag `v2.0.0`). Extracted claude-workflow into three repos (cooling-off WAIVED 2026-06-02): SPLIT-01 → `agenticapps-shared` v1.0.0 (migration runner + drift test + fixtures, consumed as git submodule, locked); SPLIT-02 → `agenticapps-observability` v0.11.1 (skill renamed `add-observability`→`observability`, dual-symlink alias retained through 0.12.0); SPLIT-03 → `claude-workflow 2.0.0` (deleted bundled obs tree, 7 migration tombstones, migration 0022 repoint + #58 deterministic Phase Sentinel hook). Lightweight close (stub-ROADMAP model: tag already exists, no REQUIREMENTS.md/milestones-archive — consistent with the v1.21.0 close).

## Phases

### Phase 25: Fix 0019 engine + withCronMonitor — 4 gaps from callbot v1.19.0 migration

**Goal:** Close the four discrete gaps surfaced by [issue #56](https://github.com/agenticapps-eu/claude-workflow/issues/56) when migrating callbot v1.16.0 → v1.19.0: (1) 0019 engine misses wrappers anchored at `index.ts`; (2) template `CronMonitorSchedule` is structurally incompatible with Sentry's `MonitorSchedule` discriminated union; (3) `withCronMonitor`'s `E extends Record<string, unknown>` generic clashes with strict-typed `Env` interfaces; (4) ship a `withQueueMonitor` analog for Cloudflare Queue consumer handlers. After this phase, callbot can drop its hand-applied 0019 marker, its `cron-monitor.ts` LOCAL-PATCH cast, and its local `withMonitor` helper.

**Depends on:** Phase 24 (`875c90c`, add-observability v0.8.0 baseline)
**Canonical refs:**
- GitHub issue: `https://github.com/agenticapps-eu/claude-workflow/issues/56`
- Field report: `https://github.com/agenticapps-eu/callbot/pull/45` (callbot commits `adbbe5b`, `f42caaa`)
- Migration 0019 spec: `migrations/0019-sentry-crons-and-healthz.md`
- ADR-0029 (cron monitor design): `docs/decisions/0029-*.md` (if present — verify during research)
- Phase 22 SUMMARY (`.planning/phases/22-sentry-crons-healthz/SUMMARY.md`) — original cron-monitor architecture
- Phase 23 SUMMARY (`.planning/phases/23-observability-followups/SUMMARY.md`) — Guarded Shape A withCronMonitor decision

**Success Criteria** (what must be TRUE):
  1. Migration 0019 engine accepts `index.ts`-anchored wrappers (either as alias for ts-cloudflare-{worker,pages}, or with a clear REFUSE + actionable rename hint — decision in D-1)
  2. `CronMonitorSchedule` shape matches Sentry's `MonitorSchedule` discriminated union; calling `withCronMonitor` with interval schedule compiles against real Sentry types without consumer-side casts
  3. `withCronMonitor` works with strict-typed `Env` interfaces (no `[key: string]: unknown` requirement, no consumer-side `as Record<string, unknown>` cast)
  4. `withQueueMonitor` exists with Guarded Shape A semantics for Cloudflare Queue consumer handlers (`MessageBatch` first arg)
  5. callbot (or the equivalent fixture) can re-run 0019 cleanly via the engine, delete its LOCAL-PATCH, and replace its local `withMonitor` helper with upstream wrappers — no escape hatches
  6. Test surface extended: regression fixtures for each of the four findings (engine fixture for finding 1, type-level test for finding 2, generic-narrowing fixture for finding 3, withQueueMonitor coverage for finding 4)
  7. Issue #56 closed with linkback comments per finding

**Plans:** 5/5 plans complete

Plans:
- [x] 25-01-PLAN.md — Wave 0: ADRs 0031/0032/0033 + RED fixtures (08, 09, 10, 11, 0021/01) + RED queue-monitor.test.ts × 3 stacks
- [x] 25-02-PLAN.md — Wave 1: Engine D-01 fix (find + classify + resolve_anchor_files helper) — fixtures 08/09 partial-GREEN, 11 fully GREEN
- [x] 25-03-PLAN.md — Wave 2: cron-monitor.ts D-03 + D-05 across 4 sites (cf-worker, cf-pages, supabase-edge, openrouter-monitor bundled) + D-16 firewall in tests × 3 stacks
- [x] 25-04-PLAN.md — Wave 3: queue-monitor.ts × 3 TS stacks (D-07/D-08/D-09/D-10) + harness wiring; queue-monitor.test.ts × 3 GREEN; SC5 strict-Env fixture fully GREEN
- [x] 25-05-PLAN.md — Wave 4: Engine 0019 D-11 (ship queue-monitor.ts) + Migration 0019.md D-02a docs + Migration 0021 spec/engine (D-02b) + version bumps (1.20.0 / 0.9.0) + CHANGELOGs + issue #56 linkback checkpoint (SC7)

### Phase 26: worker-template hardening (deferred Phase 25.x backlog)

**Goal:** Absorb six carry-forwards into a single hardening cycle before Phase 27 — close DEF-1 (TRACE_SAMPLE_RATE unwired) via a `buildSentryOptions(env)` helper export across cf-worker + cf-pages + openrouter-monitor; close DEF-2 (REDACTED_KEYS missing HTTP-auth-header coverage) via additive expansion to `authorization`/`bearer`/`cookie`/`x-api-key` across all 5 template stacks; close DEF-3 (module-level singletons) via ADR-0034 + idempotency tests × 4 stacks (NO refactor — invariant documented, deferred candidates noted); close F-2 (harness drift) via patch-pinned vitest/`~3.2.4` × 3 heredocs + @sentry/cloudflare/`~8.55.0` × 2 heredocs + policy comment; close CR-D (engine false-positive) via content-marker firewall in `_filter_index_ts_requires_co_anchor` + new RED→GREEN fixture 13; close CR-E (TS1038 + exit-0 mask in fixture 0021/04) via canonical `interface Console + declare var` + honest fail-fast. Plus `.gitignore` extension to cf-worker, cf-pages, supabase-edge, ts-react-vite, go-fly-http (5 new files with Phase 24/26 provenance headers). Versions: add-observability 0.9.0 → 0.10.0 (minor — additive); claude-workflow 1.20.0 → 1.20.1 (patch — engine refinement + harness pins + fixture fix). NO Migration 0022 — template-only changes captured in CHANGELOGs (D-04).

**Depends on:** Phase 25 (`8a838e8`, v1.20.0 / 0.9.0 baseline)
**Canonical refs:**
- Context: `.planning/phases/26-worker-template-hardening/26-CONTEXT.md` (D-01..D-10a LOCKED user decisions)
- Research: `.planning/phases/26-worker-template-hardening/26-RESEARCH.md` (validation architecture, threat seed, 6 risk corrections to CONTEXT, OQ-1..OQ-6 answers)
- Validation: `.planning/phases/26-worker-template-hardening/26-VALIDATION.md` (per-decision grep map + Wave 0 RED requirements)
- Phase 24 SUMMARY — DEF-1/2/3 + F-2 source: `.planning/phases/24-openrouter-integration-kit/SUMMARY.md`
- Phase 25 audit-time vitest@^3.0.0/vite-node drift: `.planning/phases/25-fix-0019-engine-and-cron-wrappers/25-VALIDATION.md` §Environmental caveat
- Phase 25 CodeRabbit residuals D + E: `.planning/phases/25-fix-0019-engine-and-cron-wrappers/25-REVIEW.md`
- D-01 helper-naming precedent: `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:99` (`buildMonitorConfig` — `build*` prefix)
- D-21 byte-symmetry contract: Phase 25 D-21, applied to lib-observability.ts ↔ openrouter-monitor/src/observability/index.ts

**Success Criteria** (what must be TRUE):
  1. DEF-1 closed — `buildSentryOptions` exported in cf-worker + cf-pages + openrouter-monitor; `TRACE_SAMPLE_RATE` reaches `withSentry` via `withSentry(env => buildSentryOptions(env), withObservability(handler))` operator pattern; env-additions.md × 3 documents the wiring
  2. DEF-2 closed — REDACTED_KEYS default contains `authorization`, `bearer`, `cookie`, `x-api-key` across 5 stacks (cf-worker, cf-pages, supabase-edge, ts-react-vite, go-fly-http) AND existing 10 entries preserved (additive; codex Risk 5)
  3. DEF-3 closed — ADR-0034 exists; idempotency test PASS across 4 stacks (cf-worker last-call-wins; cf-pages last-call-wins; supabase-edge first-call-wins via existing `if (initialized) return`; openrouter byte-symmetric to cf-worker)
  4. F-2 closed — `vitest ~3.2.4` pinned in 3 harness heredocs; `@sentry/cloudflare ~8.55.0` pinned in 2 harness heredocs; policy comment block at top of run-template-tests.sh
  5. CR-D closed — `_filter_index_ts_requires_co_anchor` extended with content-marker grep; fixture `13-index-ts-without-observability-content` exists and PASSES (SKIP_UNSUPPORTED + no .observability-0019.patch emitted for vanilla pair)
  6. CR-E closed — `0021/04/types.d.ts` uses canonical `interface Console + declare var`; `0021/04/verify.sh` no longer `exit 0`s on npx absent (fail-fast); fixture 04 still GREEN
  7. .gitignore extended to 4 new stacks (cf-worker, cf-pages, supabase-edge, ts-react-vite, go-fly-http) with Phase 24/26 provenance headers
  8. Versions bumped: add-observability 0.9.0 → 0.10.0 (CHANGELOG includes UPGRADE NOTE for T1 mitigation); claude-workflow 1.20.0 → 1.20.1
  9. Byte-symmetry: `diff -q cf-worker/lib-observability.ts openrouter-monitor/src/observability/index.ts` returns empty
  10. ASVS L1 security gate satisfied — zero HIGH threats across all 3 plans

**Plans:** 3/3 plans complete

Plans:
- [x] 26-01-PLAN.md — Wave 0: ADR-0034 + RED fixture 13 + RED idempotency test stubs × 4 stacks (sets up Nyquist RED baseline)
- [x] 26-02-PLAN.md — Wave 2: Template edits — `buildSentryOptions` helper × 3 stacks (D-01, byte-symmetric); env-additions.md × 3 (D-01a); REDACTED_KEYS additive expansion × 5 meta.yaml + 5 policy.md.template (D-05, D-05b); .gitignore × 5 new files (D-08, D-08a); GREEN-flip 4 idempotency tests (D-02a)
- [x] 26-03-PLAN.md — Wave 3: Harness pins × 5 + policy comment (D-03, D-03a, D-03b); engine content-marker firewall + fixture 13 GREEN-flip (D-06); fixture 0021/04 TS1038 + exit-0 fix (D-07a, D-07b); version bumps + CHANGELOGs (D-10, D-10a). **D-04a decision: SKIP migrations/0022-worker-template-hardening.md** — template-only changes don't fit the migration chain (RESEARCH §D-04a + CONTEXT D-04 rationale).

### Phase 27: 1.21.0 stable baseline (SPLIT-00 gate)

**Goal:** Ship claude-workflow 1.21.0 as the cooled-off, stable baseline that downstream factiv repos (cparx, callbot, fx-signal-agent) upgrade to before the three-repo split (SPLIT-01/02) begins. This phase closes PR #60's deferred WR items, establishes the canonical PROJECT.md, refreshes drifted STATE/ROADMAP tracking, and lays split-prep groundwork (gsd-tools boundary audit + ADR) — WITHOUT moving any code, so the 7-day cooling-off baseline stays stable.

**Depends on:** Phase 26 (`46bb394`, v0.10.0 / claude-workflow 1.20.0 baseline)
**Canonical refs:**
- SPLIT plan: `SPLIT-00-PREREQUISITES.md` (the workflow-side gate this phase satisfies)
- Brainstorm decisions (approved 2026-06-02): WR-04 use-helper · split-prep audit-only · milestone-archive-after-ship · minimum-viable PROJECT.md
- WR-01: `add-observability/templates/run-template-tests.sh` go-test counter (`grep -c … || echo "0"` double-count)
- WR-04: `add-observability/templates/openrouter-monitor/src/index.ts` vs `src/observability/index.ts:154` (`buildSentryOptions` export unused by the entry point)
- Byte-symmetry contract: Phase 25 D-21 / Phase 26 SC-9 (`cf-worker/lib-observability.ts ↔ openrouter-monitor/src/observability/index.ts`)

**Success Criteria** (what must be TRUE):
  1. WR-01 closed — go-test counter double-count fixed (run-template-tests.sh:633-634); firewall lines 128/130/558/559 unchanged
  2. WR-02 closed — supabase-edge D-02a test calls _resetForTest() in finally; suite GREEN
  3. WR-03 closed — direct buildSentryOptions unit tests × 3 stacks (RED→GREEN), assertions per RESEARCH Blocker-C (TRACE_SAMPLE_RATE is a baked constant)
  4. WR-04 closed — openrouter entry routes options through buildSentryOptions(env); no hardcoded tracesSampleRate: 0.1; byte-symmetry state unchanged
  5. Canonical minimum-viable .planning/PROJECT.md created (D-05)
  6. STATE.md + ROADMAP.md drift refreshed (Phase 26 merged; stale Next action fixed) (D-08)
  7. Split-prep: migrations/run-tests.sh annotated # SHARED / # WORKFLOW (audit-only, suite GREEN); ADR-0035 written; SPLIT-01 gsd-tools.cjs premise corrected (B1)
  8. SPLIT-00 gate changed to pin-by-tag (D-07c) — satisfiable under A2
  9. CHANGELOG ## [1.21.0] section added; skill/SKILL.md STAYS 1.20.0; drift test GREEN (A2 tag-only); git tag v1.21.0 created manually at ship

**Plans:** 6/6 plans complete

Plans:
- [x] 27-01-PLAN.md — Wave 1: WR-01 (go-test counter) + WR-02 (supabase-edge _resetForTest cleanup)
- [x] 27-02-PLAN.md — Wave 1: WR-03 buildSentryOptions direct unit coverage × 3 stacks (coverage-add + local sensitivity proof)
- [x] 27-03-PLAN.md — Wave 1: canonical PROJECT.md (D-05) + STATE/ROADMAP drift refresh (D-08)
- [x] 27-04-PLAN.md — Wave 1: run-tests.sh SHARED/WORKFLOW annotations + ADR-0035 + SPLIT-01 correction + SPLIT-00 pin-by-tag fix (B1, D-06/D-07c)
- [x] 27-05-PLAN.md — Wave 2 (depends 02): WR-04 openrouter entry uses buildSentryOptions(env); byte-symmetry re-verify
- [x] 27-06-PLAN.md — Wave 2 (depends 01-05, manual tag): CHANGELOG ## [1.21.0] + git tag v1.21.0 (autonomous: false)

---

## Milestone: repo-split

### Phase 28: SPLIT-01 — extract shared infrastructure to `agenticapps-shared`

**Goal:** Carve the shared migration infrastructure out of `claude-workflow` into the new repo `agenticapps-eu/agenticapps-shared`, consumed by both `claude-workflow` and the future `agenticapps-observability` as a **git submodule** at `vendor/agenticapps-shared/`. The shared layer holds the migration-runner mechanism, fixture harness, generic helpers, and the drift-test RUNNER (mechanism only — the version-coupling POLICY stays in each consumer). After this phase, `claude-workflow`'s `migrations/run-tests.sh` sources the shared lib and keeps only its WORKFLOW (per-migration) test bodies + its drift POLICY; the suite baseline `PASS=186 FAIL=4` is preserved exactly (the 4 pre-existing `test_migration_0017` failures are FIX-0017 scope, out of this phase — NOT introduced or fixed here).

**Depends on:** Phase 27 (`5aff1b1`, v1.21.0 baseline) · ADR-0035 (SHARED/WORKFLOW boundary) · SPLIT-00 gate (GREEN by waiver 2026-06-02)

**Canonical refs:**
- Plan doc: `SPLIT-01-agenticapps-shared.md` (Phase A complete; Phase C `gsd-tools.cjs` framing SUPERSEDED by ADR-0035 — real target is `run-tests.sh`)
- `docs/decisions/0035-shared-extraction-boundaries.md` — line-level SHARED/WORKFLOW boundary (canonical map = the annotations in `migrations/run-tests.sh`)
- `SPLIT-00-PREREQUISITES.md` — gate (pin-by-tag D-07c; cooling-off waived)

**Locked decisions (this session, 2026-06-02):**
- **D-28a Sharing mechanism = git submodule** at `vendor/agenticapps-shared/` (zero runtime dep, SHA-pinned). See [[split-sharing-mechanism]].
- **D-28b History = provenance-by-note.** Shared helpers are carved from the single `run-tests.sh` into clean new `migrations/lib/*.sh` files; `git filter-repo` is whole-file granularity and cannot carve functions, so `git log --follow` lineage is NOT preserved for carved code. Provenance recorded in `agenticapps-shared` CHANGELOG "Migration provenance" + commit messages referencing claude-workflow SHAs. The original SPLIT-01 acceptance criterion "every moved file's full log via git log --follow" is AMENDED accordingly (applies only to any whole-file moves, e.g. framework-generic `migrate-*.sh` / generic fixtures).

**Success Criteria** (what must be TRUE):
  1. `agenticapps-eu/agenticapps-shared` at v1.0.0 holds the carved SHARED set from `run-tests.sh` (per ADR-0035 annotations) as `migrations/lib/*.sh` + the dispatcher + fixture harness, with provenance recorded (D-28b)
  2. `claude-workflow` consumes it as a git submodule at `vendor/agenticapps-shared/`; fresh clone + CI fetch with `--recurse-submodules` documented in `install.sh`/CI
  3. `claude-workflow`'s `migrations/run-tests.sh` sources the shared lib, retains all WORKFLOW (per-migration `test_migration_00NN`) bodies + the drift-coupling POLICY, and the suite baseline is preserved EXACTLY at `PASS=186 FAIL=4` (the 4 failures are pre-existing `test_migration_0017` / FIX-0017 scope — not touched here)
  4. Drift test still PASSES: SKILL.md `version` == latest migration `to_version` (mechanism from shared, policy owned by claude-workflow)
  5. NO observability-specific code in shared (e.g. `test_meta_destinations_consistency`, `migrate-0019/0021`, fixtures 0019/0021 stay/move-to-obs); NO GSD planning code in shared
  6. No regression in any GSD command output (`/gsd-progress`, `/gsd-stats`, `/gsd-help`)
  7. `agenticapps-shared` README documents the submodule consumption pattern; claude-workflow CHANGELOG records the extraction
  8. PR merged to claude-workflow main; version bump decided at SPLIT-02 ship time (likely 2.0.0-rc.X)

**Plans:** 3/3 plans complete

Plans:
- [x] 28-01-PLAN.md -- Wave 1: carve SHARED harness fns from run-tests.sh into agenticapps-shared migrations/lib/{helpers,fixture-runner,preflight,drift-test}.sh (parameterized; provenance-by-note)
- [x] 28-02-PLAN.md -- Wave 1 (after 01): agenticapps-shared standalone test suite + _example fixture + CHANGELOG provenance + commit & tag v1.0.0
- [x] 28-03-PLAN.md -- Wave 2: claude-workflow consumes submodule pinned to v1.0.0; run-tests.sh sources lib (186/4 preserved); install.sh init; CHANGELOG; PR (checkpoint: review/merge)

### Phase 29: SPLIT-02 — extract observability to `agenticapps-observability`

**Goal:** Extract `add-observability/` → new repo `agenticapps-eu/agenticapps-observability` WITH git history (`git filter-repo`); rename skill `add-observability` → `observability` (starts 0.11.0, Option A dual-symlink alias retained 0.11.0+0.12.0); consume `agenticapps-shared` as a submodule @v1.0.0; fold three deferred obs fixes into a NEW migration **0022** that supersedes 0021 (cron-flush backport per `RESEARCH-cron-monitor-flush-fxsa.md`, #61 `buildMonitorConfig`/types.d.ts fix, queue-monitor.ts race audit) preserving the narrowed strict-Env generic (ADR-0032/SC5); verify the new repo green (0019=13, 0021=4, 0022 green, drift PASS, history preserved) and tag obs **v0.11.0**. **This is the NEW-REPO side ONLY** — claude-workflow stays fully working (COPIED out via scratch-clone filter-repo); its baseline stays `PASS=186 FAIL=4`. The breaking cleanup (delete `add-observability/`, repoint 0011, claude-workflow 2.0.0, fix #58) is Phase 30.

**Depends on:** Phase 28 (`aa1d60f`, agenticapps-shared v1.0.0 / SHA `1f5d543` baseline)
**Canonical refs:**
- Context: `.planning/phases/29-split-02-agenticapps-observability/29-CONTEXT.md` (LOCKED scope, decisions, Phase 29/30 boundary)
- Research: `.planning/phases/29-split-02-agenticapps-observability/29-RESEARCH.md` (migration-ownership audit RESOLVED — 8 move/0011 stays; drift-path pitfall; security domain)
- Validation: `.planning/phases/29-split-02-agenticapps-observability/29-VALIDATION.md`
- Plan doc: `SPLIT-02-agenticapps-observability.md` (A–H exec plan); cron-flush draft: `RESEARCH-cron-monitor-flush-fxsa.md`
- SPLIT-01 precedent: `.planning/phases/28-split-01-agenticapps-shared/28-VERIFICATION.md`

**Planner-resolved decisions (2026-06-02):**
- Migration 0022 `to_version: 0.11.0` (obs version) — makes the obs drift test pass (only the latest migration's to_version matters; Pitfall 3 Option B).
- 0017 MOVES (overrides SPLIT-02 doc line 122) — engine sources `add-observability/templates/`; its 4 known-failing fixtures (02/06/10/11) travel as a documented obs follow-up (FIX-0017 deferred).
- Flush fix scope: cron-monitor cf-worker + cf-pages + supabase-edge; queue-monitor cf-worker + cf-pages only (supabase-edge has no queue-monitor, VERIFIED). fxsa `CronMonitorConfigInput` function-form LEFT OUT (separable).

**Success Criteria** (what must be TRUE):
  1. `agenticapps-eu/agenticapps-observability` exists (private) at v0.11.0; `vendor/agenticapps-shared` submodule pinned at gitlink SHA `1f5d543`
  2. The observability tree moved WITH history — `git log --follow` works on SKILL.md, `migrations/scripts/migrate-0019.sh`, and a fixture (3+ files); 8 migrations moved, 0011 + ADR-0035 stayed
  3. Skill renamed `observability` 0.11.0; legacy `add-observability` alias resolves; `install.sh` creates both symlinks with clobber-guard
  4. Migration 0022 (supersedes 0021, immutable) lands the cron-flush + #61 + queue-audit fixes; narrowed strict-Env generic preserved; FXSA-WORKERS-6 marker reconciled; `to_version: 0.11.0`
  5. obs suite green: `run-tests.sh 0019`=13, `0021`=4, `0022` green, drift PASS; `0017`=7/4 (documented known-failures)
  6. claude-workflow baseline UNCHANGED at `PASS=186 FAIL=4` (Phase 29 only copied out)
  7. ASVS L1 security gate satisfied — STRIDE register per plan, zero unmitigated HIGH (no `--force` push, $REPO_ROOT-anchored paths, install.sh clobber-guard)
  8. obs tagged v0.11.0 + pushed; claude-workflow PR / 2.0.0 ship deferred to Phase 30

**Plans:** 5/5 plans complete

Plans:
- [x] 29-01-PLAN.md — Wave 1: bootstrap repo (private, MIT) + 0.11.0 skeleton + agenticapps-shared submodule @v1.0.0 (checkpoints: repo-create, first push)
- [x] 29-02-PLAN.md — Wave 2: extract-with-history via git filter-repo on a scratch clone (8 migrations + ADRs 0029-0034; 0011 stays); merge + push (checkpoint: push)
- [x] 29-03-PLAN.md — Wave 3: skill rename observability 0.11.0 + legacy alias + dual-symlink install.sh + source-and-keep run-tests.sh shim (obs root SKILL.md drift path)
- [x] 29-04-PLAN.md — Wave 4 (TDD): migration 0022 — explicit-flush cron-monitor (3 stacks) + queue-monitor (2 stacks) + #61 types.d.ts + ADR-0036; preserve narrowed generic
- [x] 29-05-PLAN.md — Wave 5: verify obs green (0019/0021/0022 + drift + history + dual-skill) + claude-workflow 186/4 guard + tag v0.11.0 (checkpoint: ship)

### Phase 30: SPLIT-03 — claude-workflow 2.0.0 follow-up

**Goal:** Post-split cleanup: delete `add-observability/` + the moved migrations/fixtures/ADRs from claude-workflow, repoint the observability install path, manage the `add-observability`→`observability` alias deprecation window, write the downstream upgrade story, ship `claude-workflow 2.0.0` (split = breaking-change rationale), and fix #58 (Stop-hook nag). **Unblocked — Phase 29 complete (obs v0.11.1 live).**

**Plans:** 3/3 plans complete

Plans:
- [x] 30-01-PLAN.md — Wave 1: delete add-observability/ tree + 7 moved migrations/fixtures/scripts + 6 obs ADRs; write 7 tombstones; strip 8 obs-dependent test bodies + 0011 sanity check (suite green, drift PASS, SKILL.md stays 1.20.0) — D-01
- [x] 30-02-PLAN.md — Wave 2: phase-sentinel.sh template + Stop-block swap (#58); migration 0022 (repoint to observability skill, abort-if-absent, to_version 2.0.0, #58 fold-in); SKILL.md → 2.0.0; 0022 + phase-sentinel test bodies (drift GREEN at 2.0.0) — D-02/D-03/D-04/D-07
- [~] 30-03-PLAN.md — Wave 3: Tasks 1-2 DONE (reference cleanup D-05 incl config-hooks.json L97 → observability:scan + install.sh skill-pair DROP; docs/UPGRADING.md D-06 + CHANGELOG [2.0.0]; commits 13258c3, 8a7dccd; suite PASS 149, drift PASS 2.0.0). Task 3 ship gate (CHANGELOG already in, /gsd-review, tag v2.0.0, breaking PR — human-verify checkpoint) PENDING orchestrator — D-04/D-05/D-06

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 25. Fix 0019 engine + withCronMonitor | 5/5 | Complete    | 2026-06-01 |
| 26. worker-template hardening | 3/3 | Complete (merged PR #60, 46bb394) | 2026-06-01 |
| 27. 1.21.0 stable baseline (SPLIT-00 gate) | 6/6 | Complete    | 2026-06-02 |
| 28. SPLIT-01 — agenticapps-shared extraction | 3/3 | Complete    | 2026-06-02 |
| 29. SPLIT-02 — agenticapps-observability extraction | 5/5 | Complete    | 2026-06-03 |
| 30. SPLIT-03 — claude-workflow 2.0.0 follow-up | 3/3 | Complete    | 2026-06-03 |
