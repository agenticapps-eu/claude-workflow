---
gsd_state_version: 1.0
milestone: repo-split
milestone_name: extract claude-workflow into three repos
status: planning
stopped_at: v1.21.0 shipped+merged (PR #62 `5aff1b1`, tag v1.21.0); repo-split milestone opened, SPLIT-01 Phase A pre-flight passed
last_updated: "2026-06-02T13:02:21.000Z"
last_activity: 2026-06-02
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md
See: .planning/ROADMAP.md (single-row stub, 2026-05-31 — Phase 25 + Phase 26 placeholder only)

**Core value:** Spec-first, migration-driven workflow scaffolder for AgenticApps projects.
**Current focus:** repo-split milestone — SPLIT-01 (extract `agenticapps-shared`: migration runner + drift test + fixtures via git submodule).

## Current Position

Milestone: repo-split (cooling-off WAIVED 2026-06-02)
Phase: SPLIT-01 — agenticapps-shared extraction
Plan: SPLIT-01 PLANNED — 3 plans (28-01/02/03) on branch `plan/28-split-01` (`034e685` plans + `docs(28)` CONTEXT/RESEARCH/STATE). gsd-plan-checker = VERIFICATION PASSED (all 11 dims, 8 SCs + D-28a..f covered, 2 info notes only). Phase A bootstrap already done (`agenticapps-shared` private, skeleton `d136c96`, tag `v1.0.0-pre.0`).
Status: PLANNED + REVIEWED + RE-CHECKED — ready to execute. NEXT: /gsd-execute-phase 28.
  - /gsd-review done: gemini LOW, codex HIGH (caught 4 structural blind-spots the same-LLM checker missed). All findings A1-A7 in 28-REVIEWS.md.
  - Replanned with --reviews; gsd-plan-checker re-check = VERIFICATION PASSED (A1-A7 covered, no regression). Plans committed `d1e67ba`.
  - A1 user-locked: setup_fixture demoted to claude-workflow wrapper; only extract_to shared (amends ADR-0035 9→8 SHARED).
  - (Side fix: patched ~/.claude/get-shit-done/workflows/review.md — codex/claude/gemini invocations now `< /dev/null` + timeout; the stdin-hang that bit /gsd-review 3× across repos. Survives /gsd-update via gsd-local-patches. See memory codex-exec-stdin-hang.)

**Plan shape:** Wave 1 = 28-01 (carve 9 SHARED fns → `agenticapps-shared/migrations/lib/{helpers,fixture-runner,preflight,drift-test}.sh` incl. setup_fixture 4th-arg fix + drift mechanism/policy split) → 28-02 (standalone smoke suite + CHANGELOG provenance + tag v1.0.0). Wave 2 = 28-03 (claude-workflow submodule pin @v1.0.0 + run-tests.sh source-and-keep refactor + install.sh + PR; HARD GATE PASS=186 FAIL=4 exact; autonomous:false checkpoint). **Reconciliation resolved:** baseline is 186/4 (not 190+ green); NO filter-repo needed (all migrate-*.sh are obs-specific → SPLIT-02); every carved artifact is provenance-by-note (D-28b).
Last activity: 2026-06-02

Progress: v1.21.0 milestone shipped+merged (PR #62 `5aff1b1`, tag `v1.21.0`). Lightweight close (no heavy /gsd-complete-milestone ceremony — tag already exists, project uses stub-ROADMAP model, no REQUIREMENTS.md/milestones-archive). Sharing mechanism locked = git submodule. ADR-0035 + run-tests.sh SHARED/WORKFLOW annotations (9 SHARED / 20 WORKFLOW) confirm extraction target = `migrations/run-tests.sh` + framework + fixtures (NOT `bin/gsd-tools.cjs`, which is not in-repo).

## Performance Metrics

Not tracked yet — full bootstrap deferred. Phase 24 (most recent shipped) is at commit `875c90c`, claude-workflow v1.19.0 / add-observability v0.8.0.

## Accumulated Context

### Decisions

Recent decisions affecting current work:

- **Phase 25 D-01:** 0019 engine accepts `index.ts` as alias anchor for cf-worker/cf-pages (silent; middleware co-anchor guards)
- **Phase 25 D-03:** `CronMonitorSchedule` → real discriminated union matching Sentry's `MonitorSchedule`
- **Phase 25 D-05:** `withCronMonitor<E>` generic narrowed to `{ SENTRY_DSN?: string; SERVICE_NAME?: string }`
- **Phase 25 D-07..D-11:** ship `withQueueMonitor` with Guarded Shape A + D11 multi-queue explicit-slug; migration 0019 re-rev to also copy `queue-monitor.{ts,go}`
- **Phase 25 D-13/14:** add-observability 0.8.0 → 0.9.0 (minor), claude-workflow 1.19.0 → 1.20.0 (minor)
- **Phase 24 (shipped):** OpenRouter integration kit (PR #55, ADR-0030)
- **Phase 23 / ADR-0029:** Guarded Shape A for Sentry-wrapped handlers
- **Phase 22:** Sentry Crons heartbeats + healthz endpoint convention
- [Phase 27]: WR-01: used '|| true' to suppress grep exit-1 without double-count; WR-02: _resetForTest() moved inside finally block
- [Phase 27]: Token-aware assertions in cf-worker/cf-pages tests use materialized values (SENTRY_DSN, test-service, 0.1) — harness substitutes tokens before vitest runs
- [Phase 27]: SHARED/WORKFLOW boundary pre-decided for migrations/run-tests.sh extraction (ADR-0035); bin/gsd-tools.cjs is GSD framework, not this repo
- [Phase 27]: SPLIT-00 gate changed to pin-by-tag v1.21.0/commit SHA; SKILL.md version not acceptable evidence under A2 (D-07c)
- [Phase 27]: PROJECT.md is forward-looking only — history stays in .planning/phases/ + git (D-05)
- [Phase 27]: Versioning policy section defines release/baseline tag vs skill version as distinct terms to prevent dual-version confusion
- [Phase 27]: ROADMAP.md v1.21.0 milestone entry added with tag-only framing; skill version stays 1.20.0
- [Phase 27]: WR-04: withSentry entry uses buildSentryOptions(env); snapshot-unchanged invariant confirmed; openrouter 17 tests GREEN
- [Phase 27]: A2 invariant: SKILL.md stays 1.20.0, drift test GREEN, no migration — git tag v1.21.0 deferred to ship time after PR merge

### Roadmap Evolution

- Phase 27 added (2026-06-02): 1.21.0 stable baseline (SPLIT-00 gate) — final phase of current milestone; WR-01..04, minimum-viable PROJECT.md, STATE/ROADMAP drift refresh, gsd-tools boundary audit + ADR (no extraction), bump 1.20.0 → 1.21.0.

### Pending Todos

None tracked yet — todo system not initialized at project level.

### Blockers/Concerns

- **Full ROADMAP/STATE/PROJECT retroactive bootstrap deferred** — current stubs are minimum enablers, not the full retro. Should land as its own phase before Phase 27 or so.
- **`FIX-0017-ENGINE.md` working-dir prompt** — separate scope from Phase 25 (migration 0017 vs 0019); needs its own phase eventually.
- **Untracked session noise:** `.claude/`, `AGENTS.md`, `CLAUDE.md` (the gstack-prompted one, not the canonical repo CLAUDE.md), `.planning/config.json`, `add-observability/templates/openrouter-monitor/package-lock.json`, `add-observability/templates/{ts-cloudflare-{pages,worker}}/node_modules/`. None blocking; decide whether to commit, .gitignore, or delete during a cleanup pass.

## Session Continuity

Last session: 2026-06-02T13:02:21.000Z
Stopped at: SPLIT-01 planned, reviewed (codex+gemini), revised (--reviews), re-checked PASS. On branch `plan/28-split-01`, all artifacts committed through `d1e67ba`. Ready to execute.
Resume file: .planning/phases/28-split-01-agenticapps-shared/ (28-CONTEXT, 28-RESEARCH, 28-REVIEWS, 28-0{1,2,3}-PLAN); ADR-0035 (amended by 28-01 T4 at execute time)
Next action: `/gsd-execute-phase 28`. Execution acts on TWO repos: Wave 1 (28-01,28-02) autonomous on `~/Sourcecode/agenticapps/agenticapps-shared` — carve lib (helpers/fixture-runner[extract_to only]/preflight/drift-test), broadened standalone suite, ADR-0035 amendment, record release SHA, tag v1.0.0. Wave 2 (28-03) autonomous:false on claude-workflow feature branch `split-01-agenticapps-shared` — submodule pin by gitlink SHA, run-tests.sh source-and-keep refactor (setup_fixture rebuilt as wrapper), install.sh existing-clone fix, GSD before/after diff, PR; then human-verify checkpoint (fresh-clone test + /gsd-review on diff). HARD GATE: suite stays PASS=186 FAIL=4 exactly.
