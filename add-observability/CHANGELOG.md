# add-observability — CHANGELOG

All notable changes to the `add-observability` skill. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Versioning: this skill ships an independent SemVer track from `claude-workflow`. Minor bumps reflect observable downstream behaviour changes in scaffolded templates.

## 0.9.0 — 2026-05-31

Re-rev cron-monitor + new queue-monitor for v1.19.0 projects (Phase 25, ADR-0033). Delivered via Migration 0021.

### Added

- **`queue-monitor.ts`** in `ts-cloudflare-worker` and `ts-cloudflare-pages` — Guarded Shape A semantics (ADR-0029/ADR-0033). `withQueueMonitor<E, Body>(handler, opts)` wraps a Cloudflare Queue consumer: `handlerStarted` flag prevents double-ack on `batch.ackAll()`, per-message retry on handler error, Sentry crons heartbeat via `withMonitor`. Imports `buildMonitorConfig` + `isConfigured` from `./cron-monitor` (D-19 import contract). Skipped for `ts-supabase-edge` — Deno runtime has no Cloudflare-Queue equivalent (codex H-6).

### Fixed

- **`cron-monitor.ts` — discriminated-union `CronMonitorSchedule`** (D-03, all 3 TS stacks): `{ type: "crontab"; value: string } | { type: "interval"; value: number; unit: string }` replaces bare `{ type: string; value?: ... }`. Invalid combinations (e.g., `interval` without `unit`) now caught at compile time.
- **`cron-monitor.ts` — `withCronMonitor<E>` generic narrowing** (D-05, cf-worker + openrouter-monitor): env parameter typed `E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }` so strict CallbotEnv-style envs (no index signature) compile without a cast. cf-pages retains `<R>` return-type generic per H-3. supabase-edge has no generic.
- **`cron-monitor.ts` — `buildMonitorConfig` + `isConfigured` exports** (D-19, cf-worker + cf-pages + openrouter-monitor): queue-monitor.ts imports these at runtime; missing exports would be a runtime failure disguised as a TS error. supabase-edge correctly omits the exports (no queue-monitor consumer there, per codex H-6).

### Changed

- Skill version 0.8.0 → 0.9.0 minor (new queue-monitor × 2 stacks + cron-monitor fixes × 3 stacks + Migration 0021 engine + ADR-0033).

### Notes

- Migration 0021 is the delivery vehicle: `migrate-0021-with-cron-and-queue-updates.sh` re-revs `cron-monitor.ts` and ships `queue-monitor.ts` to v1.19.0 projects. Dirty-detection refuses hand-modified `cron-monitor.ts` (emits `.observability-0021.patch`); twofold idempotency SKIP when both files already at v1.20.0 baseline.
- Migration 0019 D-11 fix: fresh applies now copy `queue-monitor.ts` to cf-worker + cf-pages wrappers (was absent pre-Phase-25).

## 0.8.0 — 2026-05-29

OpenRouter integration kit. Four SDK-first deliverables (ADR-0030):

1. `recordLLMResponseMeta` helper × 3 TS stacks (worker / pages / supabase-edge).
2. `openrouter-integration.md` — 5-section runbook with loud PII gate.
3. `templates/openrouter-monitor/` — standalone Worker scaffold (proactive budget alerting).
4. `init/INIT.md` Phase 5.5 §"Optional: LLM observability" — consent gate 4.

No migration (purely additive). Existing projects adopt via the runbook; greenfield via INIT.

See `.planning/phases/24-openrouter-integration/CONTEXT.md` for decisions (D-01 — D-19), `.planning/phases/24-openrouter-integration/24-REVIEWS.md` for the multi-AI plan review record, and `docs/decisions/0030-openrouter-integration-sdk-first.md` for the architecture rationale.

### Added

- **`recordLLMResponseMeta`** in `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`. Captures the two signals Sentry AI Monitoring's `openAIIntegration` doesn't surface — rate-limit headroom (`x-ratelimit-remaining` / `x-ratelimit-reset` headers) + cache_ratio (`prompt_tokens_details.cached_tokens / prompt_tokens` with explicit divide-by-zero guard). Dependency-injected `LogEventFn` per §10.6 destination-independence. Per-stack import paths: worker/pages use bundler-style `./index`; supabase-edge uses Deno explicit-extension `./index.ts`. Skipped for `ts-react-vite` (browser must not hold OpenRouter keys) and `go-fly-http` (no Go LLM consumer in scope). +7 fixtures per stack = +21 helper fixtures total.
- **`openrouter-integration.md` runbook** — 5 sections + adoption checklist + path table. Loud PII gate (`recordInputs:false / recordOutputs:false` is non-negotiable for callbot / cparx / any-real-user-data project). Carve-out: `recordInputs:true` allowed ONLY for synthetic / non-user / approved-eval data with `policy.md` approval (D-19).
- **`templates/openrouter-monitor/` standalone scaffold** — Cloudflare Worker that polls OpenRouter `/api/v1/key` on a 15-min cron. Emits `openrouter.credit_pulse` (info) always, `openrouter.credit_low` (warn) at ≥85%, `OpenRouterBudgetCriticalError` (captured via captureError) at ≥95%, `OpenRouterHealthcheckFailedError` on non-2xx / network / parse failure. Inverted-threshold misconfig + invalid env vars + `limit:null` (unlimited-key) all handled. Wrapped with `withCronMonitor` (ADR-0029 Guarded Shape A) → monitor has its own heartbeat via `openrouter-credit-check` Sentry monitor slug. Composition: `withSentry(env => ({...}))(withObservabilityScheduled(withCronMonitor(checkCredit, { monitorSlug })))` — all three layers mandatory. Ships bundled `src/observability/` subtree (canonical wrapper from `ts-cloudflare-worker`, with placeholders substituted). README leads with `keys:read`-scope warning + ships "Security & Secret Lifecycle" subsection (rotation cadence, accidental-commit prevention, leak-response runbook, operator offboarding). 12 handler test fixtures (separate `npm test` in scaffold).
- **`init/INIT.md` Phase 5.5 §"Optional: LLM observability"** — consent gate 4 (additive). Detection grep broadened beyond `package.json + src/` to catch monorepo / wrangler.toml / .dev.vars layouts. SDK-version prerequisite check (`@sentry/<host> ≥ 10.2.0`) gates the integration-insertion action.

### Changed

- Skill version 0.7.0 → 0.8.0 minor (additive — new helper across 3 stacks + new scaffold + new INIT surface + new runbook + new ADR; no removal, no migration).

### Notes

- Pre-execute multi-AI plan review (`gsd-review`) caught 4 HIGH + 5 MEDIUM issues from `codex` and `gemini` before code shipped. Notable HIGH fixes:
  - Per-stack helper import path (worker/pages `./index`; supabase-edge `./index.ts`).
  - Monitor scaffold bundles the observability subtree (skipping it would break the import chain).
  - Monitor composition uses the FULL `withSentry → withObservabilityScheduled → withCronMonitor` chain (skipping the middle layer would no-op the destinations registry silently).
  - Severity literal `"warn"` (NOT `"warning"`) — matches `Severity` union (`debug | info | warn | error | fatal`).
- Monitor scaffold pins `@sentry/cloudflare ^8.0.0` (matches the bundled wrapper baseline). The 10.2.0 minimum applies to the main app's AI Monitoring; the monitor itself makes no LLM calls.

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
