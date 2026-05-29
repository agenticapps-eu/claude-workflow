# Phase 22 — Sentry Crons heartbeats (`withCronMonitor`) + `/healthz` convention

**Branch**: `feat/sentry-crons-healthz-v1.18.0`
**Spec target**: `agenticapps-workflow-core@v0.4.0` — §10.6 (destination independence) + §10.7 (generator obligation). **No spec change.** Cron-heartbeat behavior is host-discretion under §10.6/§10.7; mandating it across all destinations is a separate future §10.x conversation.
**Version bump**: `claude-workflow 1.17.0 → 1.18.0`; `add-observability` skill `0.5.1 → 0.6.0`; `implements_spec` unchanged on both (0.4.0 / 0.3.2).
**Date opened**: 2026-05-29
**Hand-off source**: user-provided prompt ("PROMPT A — claude-workflow: Sentry Crons + Healthz convention (v1.18.0)").
**Approved design**: this CONTEXT.md is the design artifact; the upstream prompt + the consolidated design block presented and approved in-session on 2026-05-29 are the binding source. No separate `docs/superpowers/specs/` file (project convention: GSD phase CONTEXT.md is the spec home).

## Background

`add-observability` v0.5.1 ships per-stack wrappers (`withObservability`, `withObservabilityScheduled` — plus the Sentry SDK's own `withSentry` wrap applied at the entry file) whose visibility ends at request boundary. Two failure modes are invisible to the in-request capture path:

1. **Cron didn't fire.** A `ScheduledHandler` that never gets invoked (Cloudflare cron trigger misconfigured, `pg_cron` paused, fly machine down) emits zero events through `withObservabilityScheduled` — there's no error to capture if the handler never ran.
2. **Platform is up but unreachable.** A Worker that's deployed but routing-failed, a Supabase Edge function that 502s before reaching user code, a Go service that crashed and didn't restart — `captureError` can't fire from code that never executes.

Sentry's product surface already covers both gaps: **Crons** (`captureCheckIn` heartbeats) for "did the scheduled handler actually run?" and **Uptime** (HTTP probes against `/healthz`) for "is the platform up?". The generator obligation under spec §10.7 is satisfied if `add-observability` makes both trivial to opt into without breaking the v0.5.x wrapper interface.

This phase ships three deliverables in one PR that close those gaps without changing any existing export's signature:

1. A new **optional** `withCronMonitor` wrapper (TS) / `WithCronMonitor` helper (Go) — additive export that composes with the existing scheduled wrapper.
2. A per-stack `healthz-snippet.{ts,go}` template — **copy-only**, not auto-mounted; operator decides where it lives.
3. An operator runbook (`add-observability/uptime-setup-runbook.md`) — Sentry UI configuration walk-through for Crons + Uptime + `policy.md` cross-link.

## Goals (must-haves)

| # | Goal | Evidence shape |
|---|------|----------------|
| G1 | `withCronMonitor` exported from 4 stacks (worker / pages / supabase-edge / go-fly-http); react-vite skipped | Per-stack `middleware.{ts,go}` exports `withCronMonitor` / `WithCronMonitor`; signature matches §3 of this CONTEXT; importable in isolation; `tsc --noEmit` / `go build` clean. |
| G2 | All v0.5.1 template exports byte-identical (§10.1) | TS exports diff-clean against 1.17.0: `init`, `parseTraceparent`, `newRootContext`, `formatTraceparent`, `runWithContext`, `getActiveContext`, `startSpan`, `logEvent`, `captureError`, `withObservability`, `withObservabilityScheduled`, `instrumentedFetch`, `tracedFetch`. Go exports diff-clean: `Init`, `ParseTraceparent`, `NewRootContext`, `FormatTraceparent`, `WithContext`, `FromContext`, `StartSpan`, `LogEvent`, `CaptureError`, `Middleware`, `NewTracingTransport`, `Flush`. (`withSentry` is operator-applied from `@sentry/cloudflare` at the entry file — not a template export.) Existing 170 template-suite tests pass unchanged. |
| G3 | Cron heartbeats fire in 3 cases, fail-safe in 1 | Per stack × 3 tests: (a) happy → `captureCheckIn(in_progress)` + `captureCheckIn(ok)`; (b) handler throws → `captureCheckIn(in_progress)` + `captureCheckIn(error)` + original error re-thrown; (c) `SENTRY_DSN` unset → 0 checkins, handler runs, no exception. ~12 new tests. |
| G4 | Slug resolution honors 3-source precedence | Per-stack test: explicit `config.monitorSlug` wins → env var `SENTRY_CRON_MONITOR_SLUG_<HANDLER>` 2nd → auto-derived `${serviceName}:${cronExpr}` 3rd. Auto-derive falling back to `${serviceName}:scheduled` when cron expression unavailable (pages). |
| G5 | `healthz-snippet.{ts,go}` ships in 4 stacks with copy-only contract | Each snippet file has top-of-file `// Copy this file…` comment; in-file test asserts 200 `{"status":"ok"}` on stub-pass and 503 `{"status":"degraded", "checks": {...}}` on stub-fail with per-check breakdown. Snippet does **not** route through `withObservability` (Decision D, no Sentry transaction noise). |
| G6 | Migration 0019 adopts the new exports on existing v1.17.0 projects with §10.7 consent | `migrations/0019-sentry-crons-and-healthz.md` (`from_version: 1.17.0`, `to_version: 1.18.0`) + 5 fixtures (`01-fresh-apply`, `02-already-applied`, `03-hand-modified-refuse`, `04-no-scheduled-handlers-project`, `05-multi-module-root`). Content-hash refuse on hand-modified wrappers mirrors 0017's style-insensitive canonicalization. |
| G7 | Operator runbook published | `add-observability/uptime-setup-runbook.md` covers Crons-setup-per-slug, Uptime-setup-per-endpoint, `policy.md` "Out-of-process monitors" section template. ~150 lines. |
| G8 | Version bumps + CHANGELOG + ADR-0028 + green suites | `skill/SKILL.md` → `1.18.0`; `add-observability/SKILL.md` → `0.6.0`; `docs/decisions/0028-sentry-crons-healthz-conventions.md` records host-discretion-not-spec-mandate trade-off; `CHANGELOG [1.18.0]` entry; `migrations/run-tests.sh` PASS=prior+0019-cases FAIL=0; template suite PASS across 5 stacks. |

## Decisions locked (binding for planner)

**D1 — Separate wrapper, not config option.** `withCronMonitor` is its own export. Composes with `withObservabilityScheduled` (no signature change). Rationale: keeps the scheduled wrapper API surface frozen per the v0.5.x compatibility constraint; lets future cron-only knobs (`maxRuntimeSeconds`, `schedule` overrides) land without churning the general scheduled wrapper.

**D2 — No Axiom mirroring of checkins.** Sentry Crons UI is the value prop; mirroring heartbeats to Axiom doubles signal surface without obvious operator value. Axiom path stays log-only. (Resolves prompt Open Q1.)

**D3 — Slug is stable; commit SHA goes to Sentry `environment`/`release` context, not the slug.** Sentry treats slugs as long-lived monitor identifiers; cycling per deploy creates one monitor per commit and silently breaks the missed-checkin alert continuity (Sentry won't fire alerts on a monitor that never received a single checkin). (Resolves prompt Open Q2.)

**D4 — `/healthz` is NOT wrapped by `withObservability`.** Uptime probes hit `/healthz` every 1–15 min × N regions — that's noise that crowds Sentry's transaction view and obscures real traffic patterns. `/healthz` is observable via Sentry Uptime alone; the snippet uses raw `Response` / `http.HandlerFunc`. (Resolves prompt Open Q3.)

**D5 — Composition order: `withSentry(withObservabilityScheduled(withCronMonitor(handler)))`** (worker & supabase-edge). `withCronMonitor` is innermost so its `try/catch` runs first on handler exceptions and the rethrown error still propagates to `withObservabilityScheduled`'s capture path. `withSentry` outermost so the Sentry hub is initialized before any `captureCheckIn` call. Documented per-stack in `init/INIT.md` Phase 5 rewrite-shape sections.

**D6 — Slug resolution precedence (3-source):**
1. Explicit `config.monitorSlug` arg.
2. Env var `SENTRY_CRON_MONITOR_SLUG_<HANDLER_NAME>` (case-insensitive match, hyphens→underscores).
3. Auto-derived: `${serviceName}:${cronExpression}` (worker, go), `${serviceName}:scheduled` (pages, supabase-edge when expression unavailable).

**D7 — Healthz snippet is copy-only, not auto-mounted.** Each snippet ships with a top-of-file warning comment and an in-file test that imports the handler function directly. `init` doesn't mount it; the runbook tells the operator where to copy it.

**D8 — Hand-modified-wrapper refuse mirrors 0017.** Migration 0019 uses the same style-insensitive canonical content-hash check that 0017 settled on (PR #47). Hand-modified wrappers refuse with diff + guidance per §10.7.

**D9 — SKILL.md drift hotfix folded as commit 1 of this branch.** PR #52 (migration 0018) declared `to_version: 1.17.0` but left `skill/SKILL.md` at `version: 1.16.0`. This phase's commit 1 (`122aafa`) restores the 1:1 invariant before migration 0019 can declare `from_version: 1.17.0`. Same PR, no separate hotfix PR.

**D10 — react-vite is fully skipped.** Browser bundle has no scheduled handlers; the wrapper export and the healthz snippet are server-side concepts. Migration 0019 treats a project as "no work to do" if the only stack present is react-vite.

## Out-of-scope (explicit non-goals)

- **N1 — Spec change.** No PR to `agenticapps-workflow-core`. Implementation behavior under §10.6/§10.7; mandatory cron heartbeating across destinations is future §10.x work.
- **N2 — Axiom destination changes.** Axiom adapter byte-identical; checkins don't mirror to Axiom.
- **N3 — Adopting v1.18.0 in downstream repos.** fxsa / callbot / cparx adoption is downstream work covered by separate prompts (D / E / F in the user's sequencing plan). This PR only ships the scaffolder.
- **N4 — Guardrail test for SKILL.md drift.** The drift bug (PR #52) is fixed by commit 1, but adding a test in `migrations/run-tests.sh` that asserts `skill/SKILL.md version === latest migration to_version` is intentionally out-of-scope to keep this PR focused on the cron+healthz feature. Tracked as a follow-up in the PR body.
- **N5 — Per-handler `maxRuntimeSeconds` enforcement.** The `CronMonitorConfig.maxRuntimeSeconds` field is forwarded to Sentry as monitor config metadata, but this PR doesn't enforce it client-side via timeouts. (Operator can configure Sentry to alert when in_progress > X.)

## References

- Spec §10.6 + §10.7: `~/Sourcecode/agenticapps/agenticapps-workflow-core/spec/10-observability.md`
- ADR-0014 (observability architecture): `~/Sourcecode/agenticapps/agenticapps-workflow-core/adrs/0014-observability-architecture.md`
- ADR-0026 (`add-observability` 0.5.1 wrapper fixes): `docs/decisions/0026-add-observability-0-5-1-wrapper-fixes.md`
- ADR-0027 (post-phase observability hook): `docs/decisions/0027-postphase-observability-hook.md`
- Migration shape to mirror: `migrations/0017-add-axiom-logs-destination.md` (consent gates, content-hash refuse) and `migrations/0018-postphase-observability-hook.md` (frontmatter, idempotency).
- Existing wrapper templates: `add-observability/templates/{ts-cloudflare-worker,ts-cloudflare-pages,ts-supabase-edge,go-fly-http}/`.
- Sentry Crons: <https://docs.sentry.io/product/crons/>
- Sentry Uptime: <https://docs.sentry.io/product/uptime-monitoring/>
