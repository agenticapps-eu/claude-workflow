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

**Plans:** 1/3 plans executed

Plans:
- [x] 26-01-PLAN.md — Wave 0: ADR-0034 + RED fixture 13 + RED idempotency test stubs × 4 stacks (sets up Nyquist RED baseline)
- [ ] 26-02-PLAN.md — Wave 2: Template edits — `buildSentryOptions` helper × 3 stacks (D-01, byte-symmetric); env-additions.md × 3 (D-01a); REDACTED_KEYS additive expansion × 5 meta.yaml + 5 policy.md.template (D-05, D-05b); .gitignore × 5 new files (D-08, D-08a); GREEN-flip 4 idempotency tests (D-02a)
- [ ] 26-03-PLAN.md — Wave 3: Harness pins × 5 + policy comment (D-03, D-03a, D-03b); engine content-marker firewall + fixture 13 GREEN-flip (D-06); fixture 0021/04 TS1038 + exit-0 fix (D-07a, D-07b); version bumps + CHANGELOGs (D-10, D-10a). **D-04a decision: SKIP migrations/0022-worker-template-hardening.md** — template-only changes don't fit the migration chain (RESEARCH §D-04a + CONTEXT D-04 rationale).

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 25. Fix 0019 engine + withCronMonitor | 5/5 | Complete    | 2026-06-01 |
| 26. worker-template hardening | 1/3 | In Progress|  |
