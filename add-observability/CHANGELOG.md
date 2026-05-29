# add-observability — CHANGELOG

All notable changes to the `add-observability` skill. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Versioning: this skill ships an independent SemVer track from `claude-workflow`. Minor bumps reflect observable downstream behaviour changes in scaffolded templates.

## 0.7.0 — 2026-05-29

Phase 23 follow-ups from Phase 22's deferred review-gate residuals + user-directed `withCronMonitor` refactor. Multi-AI plan review (`23-REVIEWS.md`) refined the shape of F2 (per-stack heterogeneity), F5 (Guarded Shape A), F3 (split trap), and D-07 (honest reframe).

See `.planning/phases/23-observability-followups/CONTEXT.md` for decision basis and `docs/decisions/0029-cron-monitor-sdk-composition.md` for the F5 architectural rationale (including 5 rejected alternatives).

### Added

- **F2 — `/healthz` per-probe timeout** in all 4 stacks with per-stack heterogeneous configuration (per codex MEDIUM-5):
  - Worker: 3rd-arg override `healthzHandler(req, env, { probeTimeoutMs })` (Worker signature supports this)
  - Pages: `context.env.HEALTHZ_PROBE_TIMEOUT_MS` env var (onRequest signature runtime-fixed — no 3rd-arg path)
  - Supabase-Edge: `Deno.env.get("HEALTHZ_PROBE_TIMEOUT_MS")` env var (Deno runtime + restrictive test seam)
  - Go: `HealthzDeps.ProbeTimeout` field — **NOTE**: caps handler latency only; underlying `Get(url)` outbound call may continue in background until natural completion (codex MEDIUM-5 honest documentation)
  - Default 2000ms (TS `DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS`, Go `defaultHealthzProbeTimeout`)
  - Aborted probes report `{status: "degraded", checks: {<probe>: "timeout"}}` — string `"timeout"` distinguishes timeout from genuine probe failure
  - TS implementation uses `AbortController` + `setTimeout`/`clearTimeout` in `try/finally` (per gemini MEDIUM-1; NOT `Promise.race` with abort-rejection — prevents unhandled promise rejections)
- **`Sentry.withMonitor` Guarded composition** in 3 TS stacks' `withCronMonitor` (worker, pages, supabase-edge) — see "Changed" below for narrowed regression + honest isolation-scope semantic.
- **`withIsolationScope` wrapping per cron run** (via `Sentry.withMonitor`). Each cron invocation now runs in its own Sentry scope. **HONEST SEMANTIC (per codex MEDIUM):** tags, breadcrumbs, and user-context no longer leak between consecutive runs (intended benefit) — BUT handler-set scope state (`Sentry.setTag`, breadcrumbs set inside the cron body) may NOT be visible to outer error-capture handlers after isolation unwinds. Downstream consumers relying on cron-body scope mutations becoming visible to outer error handlers will see different behaviour.
- **`docs/decisions/0029-cron-monitor-sdk-composition.md`** ADR (authored in Wave 0 — before code — per codex Suggestion 7) capturing Guarded Shape A reasoning with 5 rejected shapes (incl. original Shape A unguarded).

### Changed

- **`withCronMonitor` (TS stacks) — Guarded Shape A refactor.** The in_progress / ok / error lifecycle is now composed via `Sentry.withMonitor` with a `handlerStarted` flag guard. If Sentry transport fails BEFORE the callback runs (pre-callback `in_progress` check-in failure), the handler falls back to running UNMONITORED — preserving the "cron always runs" contract. If transport fails AFTER the handler completed (post-callback check-in), the error propagates to the outer wrapper. The outer fail-safe + 3-source slug resolution + monitorConfig build are preserved verbatim. Per-stack net LOC delta: ~−15 lines (vs −25 for unguarded Shape A). Behavioural-parity tests added including one explicit pre-callback regression test per stack.
- **Migration 0019 atomic-refuse semantics flipped (D-07 — honest reframe per codex MEDIUM-6).** The default refuse path NO LONGER WRITES TO CLEAN ROOTS. DIRTY roots still receive `.observability-0019.patch` + `.gitignore` entries for splice recovery (the dirty-root artifacts were always present — this is the expected recovery path). Operators who want v0.6.0 "patches everywhere on refuse" for manual splice-aid pass `--allow-partial` (CLI) or `ALLOW_PARTIAL=1` (env). Flag wins over env; both must explicitly opt in.

### Regressed (documented — NARROWED vs original Shape A)

- **R02/R04 SDK-error swallow drops only for POST-callback errors** in `withCronMonitor`. Pre-callback errors (Sentry transport failing on `in_progress`) trigger the Guarded fallback — handler runs unmonitored, no propagation. POST-callback errors (transport failing on `ok`/`error` after handler completed) propagate to the outer `withObservabilityScheduled` capture path. **Operator action**: if your outer wrapper catches SDK errors, no change needed. If you relied on silent swallow to keep cron handlers running through Sentry outages, the new behaviour: pre-callback failures fall back to unmonitored execution; post-callback failures surface via outer wrapper. `SENTRY_DEBUG=1` no longer surfaces SDK call failures from inside `withCronMonitor`.

### Internal

- **F1** — `add-observability/init/INIT.md` Phase 5 per-stack subsections (worker, pages, supabase-edge, go) gained ≤5-line `withCronMonitor` composition notes citing D5a/D5b/D5d composition order with file:line links.
- **F3** — Migration test harness (`migrations/run-tests.sh`) and migration-0019 engine added **SPLIT trap design** (codex HIGH-2): `EXIT` runs cleanup silently (idempotent, no warning); `INT` runs cleanup then `exit 130`; `TERM` runs cleanup then `exit 143`. Path-validated test-only `--pause-between-passes <signal-file>` flag with `${TMPDIR:-/tmp}` default and allow-list prefix matching (`${TMPDIR:-/tmp}/sigterm-test-*` OR `migrations/test-fixtures/0019/*/sigterm-*`).
- **F4** — `migrations/run-tests.sh` added `test-skill-md-version-matches-latest-migration-to-version`. Dispatcher extended in Wave 0 to support new named filters (codex MEDIUM-7).
- **D-09** — `add-observability/templates/go-fly-http/cron_monitor.go` package doc gained ≤5-line note: `sentry-go` ships no `WithMonitor` equivalent.
- **Multi-AI plan review** — Phase 23 underwent a `/gsd-review` pass (`23-REVIEWS.md`); codex HIGH verdict + gemini MEDIUM-1 fed back into 9 revisions before execute. ADR-0029 documents the empirical evidence supporting Guarded Shape A.

### Operator migration notes

Existing installs already have v0.6.0's `cron-monitor.{ts,go}` and `healthz-snippet.{ts,go}` copied. No auto-retrofit (forward-only template change per N2). Paths:
1. **Stay on v0.6.0**: do nothing.
2. **Adopt v0.7.0**: re-copy updated templates. The narrowed regression applies only to post-callback errors; verify your outer wrapper catches SDK transport failures.
3. **D-07 operators**: if your automation relied on patches landing in clean roots on refuse, add `--allow-partial` to your invocations or set `ALLOW_PARTIAL=1`.
