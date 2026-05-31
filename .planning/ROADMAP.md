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
- 🚧 **v1.20.x worker-template hardening + 0019 engine fixes** — Phases 25-26 (in progress)

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

**Plans:** TBD (will be set by `/gsd-plan-phase 25`)

### Phase 26: worker-template hardening (deferred Phase 25.x backlog)

**Goal:** Absorb the four carry-forwards from PR #55's `session-handoff.md`: DEF-1 (TRACE_SAMPLE_RATE unwired), DEF-2 (REDACTED_KEYS missing authorization/bearer), DEF-3 (module-level mutable singletons), F-2 (no tracked package-lock.json policy), plus extending Phase 24's `.gitignore` shape from `openrouter-monitor` to `ts-cloudflare-worker`, `ts-cloudflare-pages`, and `ts-supabase-edge` templates. Same fix-shape applied symmetrically across the four observability template directories.

**Depends on:** Phase 25
**Plans:** TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 25. Fix 0019 engine + withCronMonitor | 0/TBD | Not started | - |
| 26. worker-template hardening | 0/TBD | Not started | - |
