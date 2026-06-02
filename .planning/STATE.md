---
gsd_state_version: 1.0
milestone: v1.21.0
milestone_name: stable baseline (SPLIT-00 gate)
status: verifying
stopped_at: Completed 27-06-PLAN.md (Task 1 done; Task 2 git tag deferred to ship time)
last_updated: "2026-06-02T11:03:40.435Z"
last_activity: 2026-06-02
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 14
  completed_plans: 14
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md
See: .planning/ROADMAP.md (single-row stub, 2026-05-31 — Phase 25 + Phase 26 placeholder only)

**Core value:** Spec-first, migration-driven workflow scaffolder for AgenticApps projects.
**Current focus:** Phase 27 — 1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum-

## Current Position

Phase: 27
Plan: Not started
Status: Phase complete — ready for verification
Last activity: 2026-06-02

Progress: Phase 25 complete + merged (5/5 plans); Phase 26 complete + merged — PR #60, commit `46bb394`

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

Last session: 2026-06-02T10:48:36.854Z
Stopped at: Completed 27-06-PLAN.md (Task 1 done; Task 2 git tag deferred to ship time)
Resume file: None
Next action: Execute remaining Phase 27 plans (27-05, 27-06) — WR-04 openrouter entry uses buildSentryOptions(env) + byte-symmetry re-verify (27-05); CHANGELOG ## [1.21.0] + git tag v1.21.0 (27-06, autonomous: false).
