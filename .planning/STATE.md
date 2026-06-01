---
gsd_state_version: 1.0
milestone: v1.20.0
milestone_name: worker-template-hardening-and-0019-engine
status: merged
stopped_at: Phase 25 merged to main as `8a838e8 v1.20.0 fix(#56): 0019 engine + withCronMonitor/withQueueMonitor + Migration 0021 (#57)`. Ships claude-workflow v1.20.0 + add-observability 0.9.0.
last_updated: "2026-06-01T09:50:00.000Z"
last_activity: 2026-06-01
progress:
  total_phases: 2
  completed_phases: 1
  total_plans: 5
  completed_plans: 5
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (does not yet exist — full retroactive bootstrap deferred)
See: .planning/ROADMAP.md (single-row stub, 2026-05-31 — Phase 25 + Phase 26 placeholder only)

**Core value:** Spec-first, migration-driven workflow scaffolder for AgenticApps projects.
**Current focus:** Phase 25 merged (`8a838e8`) → Phase 26 — worker-template hardening (next to discuss)

## Current Position

Phase: 25 MERGED → 26 (next to discuss)
Plan: 5/5 complete for Phase 25
Status: Phase 25 squash-merged to main as `8a838e8` on 2026-06-01; v1.20.0 + add-observability 0.9.0 live
Last activity: 2026-06-01

Progress: Phase 25 complete + merged (5/5 plans); Phase 26 not yet discussed

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

### Pending Todos

None tracked yet — todo system not initialized at project level.

### Blockers/Concerns

- **Full ROADMAP/STATE/PROJECT retroactive bootstrap deferred** — current stubs are minimum enablers, not the full retro. Should land as its own phase before Phase 27 or so.
- **`FIX-0017-ENGINE.md` working-dir prompt** — separate scope from Phase 25 (migration 0017 vs 0019); needs its own phase eventually.
- **Untracked session noise:** `.claude/`, `AGENTS.md`, `CLAUDE.md` (the gstack-prompted one, not the canonical repo CLAUDE.md), `.planning/config.json`, `add-observability/templates/openrouter-monitor/package-lock.json`, `add-observability/templates/{ts-cloudflare-{pages,worker}}/node_modules/`. None blocking; decide whether to commit, .gitignore, or delete during a cleanup pass.

## Session Continuity

Last session: 2026-06-01 — Phase 25 execution + audit + ship + merge
Stopped at: Phase 25 merged to main as `8a838e8 v1.20.0 ... (#57)` after 2-round CodeRabbit cycle (5/18 actionable closed by `5226a22` + `efec4e2`, 13 remaining are markdown-lint nitpicks + 2 parked design-call items). Branch `feat/fix-0019-engine-and-cron-wrappers-v1.20.0` deleted locally. v1.20.0 + add-observability 0.9.0 live on main.
Resume file: `.planning/STATE.md` (this file) — next action is `/gsd-discuss-phase 26`.
Next action: `/gsd-discuss-phase 26` for worker-template hardening. Scope: DEF-1/2/3 + F-2 carry-forwards from PR #55 + upstream `vitest@3.2.5` / `vite-node@3.2.5` registry-drift pin (flagged at `25-VALIDATION.md` audit-time caveat) + `_filter_index_ts_requires_co_anchor` content-marker firewall (CodeRabbit finding D, `migrate-0019-...sh:233`) + `0021/04 verify.sh` exit-0-when-npx-missing mask + TS1038 console declaration in `types.d.ts:63` (CodeRabbit finding E).
