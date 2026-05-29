---
phase: 23-observability-followups
plan: 01
type: execute
wave: multi
depends_on: []
files_modified:
  - add-observability/init/INIT.md
  - add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts
  - add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts
  - add-observability/templates/ts-supabase-edge/healthz-snippet.ts
  - add-observability/templates/go-fly-http/healthz_snippet.go
  - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts
  - add-observability/templates/ts-cloudflare-pages/cron-monitor.ts
  - add-observability/templates/ts-supabase-edge/cron-monitor.ts
  - add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts
  - add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts
  - add-observability/templates/ts-supabase-edge/cron-monitor.test.ts
  - add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts
  - add-observability/templates/ts-cloudflare-pages/healthz-snippet.test.ts
  - add-observability/templates/ts-supabase-edge/healthz-snippet.test.ts
  - add-observability/templates/go-fly-http/cron_monitor.go
  - add-observability/templates/go-fly-http/healthz_snippet_test.go
  - add-observability/SKILL.md
  - add-observability/CHANGELOG.md
  - migrations/run-tests.sh
  - migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh
  - migrations/test-fixtures/0019/07-allow-partial-emits-patches/setup.sh
  - migrations/test-fixtures/0019/07-allow-partial-emits-patches/verify.sh
  - migrations/test-fixtures/0019/07-allow-partial-emits-patches/expected-exit
  - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
  - docs/decisions/0029-cron-monitor-sdk-composition.md
autonomous: true
requirements: []
must_haves:
  truths:
    - "INIT.md Phase 5 subsections (worker, pages, supabase-edge, go) each cite withCronMonitor with a file:line link into cron-monitor.{ts,go}; react-vite subsection unchanged"
    - "All 4 /healthz snippets ship a per-probe timeout — per D-03 (revised post-review for per-stack heterogeneity): Worker uses caller-overridable opts arg; Pages reads PROBE_TIMEOUT_MS from context.env (fallback 2000); Supabase-Edge uses module-constant configuration; Go documents timeout-caps-handler-only honestly (cannot cancel inner Get(url))"
    - "TS healthz snippets use AbortController + setTimeout/clearTimeout pattern in a try/finally (no Promise.race + abort-rejection; no unhandled rejections per gemini MEDIUM-1)"
    - "Aborted probes report as {status: degraded, checks: {<probeName>: 'timeout'}} (string sentinel distinguishes timeout from genuine false)"
    - "migrations/run-tests.sh dispatcher EXTENDED in Wave 0 to support new test names (test-skill-md-version-matches-latest-migration-to-version, test-sigterm-mid-apply-preserves-state) — precondition for Tasks 1.3 + 3.1"
    - "migrations/run-tests.sh and templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh have SPLIT trap design: EXIT trap is silent + idempotent (no warning output); INT trap runs cleanup then exits 130; TERM trap runs cleanup then exits 143"
    - "Test test-sigterm-mid-apply-preserves-state uses the test-only --pause-between-passes <signal-file> engine flag; passes deterministically with no sleeps; trap fires only on signal (cleanup output absent when test exits 0 normally)"
    - "Test test-skill-md-version-matches-latest-migration-to-version asserts skill/SKILL.md version equals the highest-numbered migration file's to_version using only grep + awk (no yq)"
    - "All 3 TS cron-monitor.ts files preserve lines 137-148 verbatim (fail-safe + slug resolution + monitorConfig build) and replace lines 148-181 with the GUARDED Shape A block per CONTEXT.md D-08 (handlerStarted flag + pre-callback fallback to unmonitored handler)"
    - "Each of the 3 TS cron-monitor.test.ts files contains: (a) F5.1-F5.5 behavioural-parity tests asserting Sentry.withMonitor is called with (slug, callback, monitorConfig) and captureCheckIn is NOT called directly from wrapper; (b) ONE new regression test 'Sentry check-in setup throws before callback → handler still runs unmonitored, no crash' (per codex Suggestion 2)"
    - "Supabase Task 2.3 verifies @sentry/deno exports withMonitor BEFORE editing implementation; introduces _setWithMonitorForTest seam as Deno-friendly indirection"
    - "Go templates/go-fly-http/cron_monitor.go gains a ≤5-line package-doc note explaining sentry-go ships no WithMonitor equivalent; symbol body unchanged"
    - "Migration 0019's emit_refuse_artifacts function no longer emits .observability-0019.patch to CLEAN_DIRS in the default refuse path; --allow-partial (or ALLOW_PARTIAL=true env) restores the emit-to-all-roots behaviour. Operator-facing language honestly states 'default refuse no longer touches clean roots; dirty roots still get recovery artifacts' (per codex MEDIUM-6 — narrow path / honest reframe)"
    - "Fixture 06 verify.sh asserts the new default: clean roots receive NO patches; only the dirty root receives a patch on default refuse"
    - "New fixture 07 exercises --allow-partial and asserts clean roots are migrated, dirty root is skipped + patched"
    - "add-observability/SKILL.md version field is 0.7.0"
    - "add-observability/CHANGELOG.md has a 0.7.0 entry with: (a) F2 per-stack heterogeneous timeout (D-03 narrowed); (b) F5 GUARDED Shape A — pre-callback errors fall back to unmonitored, post-callback errors propagate (R02/R04 regression narrowed to post-callback); (c) withIsolationScope semantic honest note (handler-set scope state may not leak to outer capture after isolation unwinds, per codex MEDIUM); (d) D-07 honest reframe (default refuse no longer touches clean roots; dirty roots still receive recovery artifacts)"
    - "docs/decisions/0029-cron-monitor-sdk-composition.md exists in Wave 0 (NOT Wave 5 — moved earlier per codex Suggestion 7) with Context, Decision (Guarded Shape A), Alternatives Rejected including original-Shape-A + B + C + D + F (5 rejected), Codex's pre-callback-throw empirical evidence, and Consequences"
    - "gitnexus_detect_changes() runs as the last acceptance criterion of EACH wave-closing task (Wave 1: Task 1.7; Wave 2: Task 2.3; Wave 3: Task 3.1; Wave 4: Task 4.2; Wave 5: Task 5.4) per codex Suggestion 8"
    - "G6 gate (REPLACED): named-test-presence check (grep for new test names in run-tests.sh + run-template-tests.sh output) + overall harness exit code 0. NO numeric counter (per codex MEDIUM-7 — harness has no test-total summary)"
    - "Full migration test harness (migrations/run-tests.sh) passes after all changes; full template test harness (add-observability/templates/run-template-tests.sh all) passes after all changes"
  artifacts:
    - path: "docs/decisions/0029-cron-monitor-sdk-composition.md"
      provides: "ADR-0029 capturing D-08 Guarded Shape A rationale + 5 rejected shapes incl. original Shape A — AUTHORED IN WAVE 0 (before code) per codex Suggestion 7"
      contains: "Guarded Shape A"
    - path: "migrations/run-tests.sh"
      provides: "Wave 0 dispatcher extension (new test names) + F3 sigterm test + F4 skill-md drift test + split trap (EXIT silent / INT exit 130 / TERM exit 143)"
      contains: "test-sigterm-mid-apply-preserves-state"
    - path: "add-observability/init/INIT.md"
      provides: "F1 per-stack Phase 5 composition notes"
      contains: "withCronMonitor"
    - path: "add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts"
      provides: "F2 TS worker per-probe timeout — AbortController + setTimeout/clearTimeout (Worker keeps 3rd-arg override)"
      contains: "AbortController"
    - path: "add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts"
      provides: "F2 TS pages per-probe timeout — context.env.HEALTHZ_PROBE_TIMEOUT_MS (Pages onRequest signature has no 3rd-arg override path)"
      contains: "HEALTHZ_PROBE_TIMEOUT_MS"
    - path: "add-observability/templates/ts-supabase-edge/healthz-snippet.ts"
      provides: "F2 TS supabase-edge per-probe timeout — module-constant or env-var (planner picks at execute time matching Deno test-seam constraints)"
      contains: "PROBE_TIMEOUT_MS"
    - path: "add-observability/templates/go-fly-http/healthz_snippet.go"
      provides: "F2 Go per-probe timeout — honestly documented as 'caps handler latency, NOT inner Get(url)' per codex MEDIUM-5"
      contains: "defaultHealthzProbeTimeout"
    - path: "add-observability/templates/ts-cloudflare-worker/cron-monitor.ts"
      provides: "F5 Guarded Shape A composition (per CONTEXT.md D-08 amended block)"
      contains: "handlerStarted"
    - path: "add-observability/templates/ts-cloudflare-pages/cron-monitor.ts"
      provides: "F5 Guarded Shape A composition (pages)"
      contains: "handlerStarted"
    - path: "add-observability/templates/ts-supabase-edge/cron-monitor.ts"
      provides: "F5 Guarded Shape A composition (supabase-edge) with _setWithMonitorForTest seam"
      contains: "handlerStarted"
    - path: "add-observability/templates/go-fly-http/cron_monitor.go"
      provides: "D-09 sentry-go SDK gap doc note"
      contains: "sentry-go"
    - path: "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
      provides: "F3 split trap (EXIT silent / INT exit 130 / TERM exit 143); D-07 default-flip in emit_refuse_artifacts"
      contains: "ALLOW_PARTIAL"
    - path: "migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh"
      provides: "D-07 fixture 06 flipped assertion"
      contains: "no patch"
    - path: "migrations/test-fixtures/0019/07-allow-partial-emits-patches/verify.sh"
      provides: "D-07 fixture 07 --allow-partial path"
      contains: "allow-partial"
    - path: "add-observability/SKILL.md"
      provides: "D-01 version bump 0.6.0 → 0.7.0"
      contains: "version: 0.7.0"
    - path: "add-observability/CHANGELOG.md"
      provides: "D-01 0.7.0 release notes with honest reframing per codex MEDIUM-4/5/6"
      contains: "0.7.0"
  key_links:
    - from: "add-observability/templates/ts-cloudflare-worker/cron-monitor.ts"
      to: "@sentry/cloudflare"
      via: "Guarded Sentry.withMonitor(monitorSlug, () => { handlerStarted = true; return handler(...); }, monitorConfig) with try/catch fallback"
      pattern: "handlerStarted"
    - from: "add-observability/templates/ts-cloudflare-pages/cron-monitor.ts"
      to: "@sentry/cloudflare"
      via: "Guarded Sentry.withMonitor with handlerStarted flag"
      pattern: "handlerStarted"
    - from: "add-observability/templates/ts-supabase-edge/cron-monitor.ts"
      to: "@sentry/deno"
      via: "Guarded Sentry.withMonitor via _setWithMonitorForTest seam"
      pattern: "handlerStarted"
    - from: "add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts"
      to: "global AbortController"
      via: "AbortController + setTimeout/clearTimeout pattern (no Promise.race rejection)"
      pattern: "AbortController"
    - from: "add-observability/templates/go-fly-http/healthz_snippet.go"
      to: "stdlib context"
      via: "context.WithTimeout(r.Context(), defaultHealthzProbeTimeout) — caps handler only (NOT inner Get(url))"
      pattern: "context\\.WithTimeout\\("
    - from: "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
      to: "split trap handlers"
      via: "trap on_exit EXIT (silent); trap 'cleanup; exit 130' INT; trap 'cleanup; exit 143' TERM"
      pattern: "trap.*INT|trap.*TERM"
    - from: "migrations/run-tests.sh"
      to: "skill/SKILL.md + migrations/<latest>.md"
      via: "test-skill-md-version-matches-latest-migration-to-version function (dispatcher extended in Wave 0)"
      pattern: "test-skill-md-version-matches-latest-migration-to-version"
    - from: "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
      to: "operator opt-in flag"
      via: "ALLOW_PARTIAL gating around clean-root patch emission (D-07 honest reframe)"
      pattern: "ALLOW_PARTIAL.*-eq 1"
---

<objective>
Ship `add-observability 0.7.0` minor — five batched follow-ups from Phase 22 plus a side-work atomic-refuse default-flip on migration 0019. **REVISED per multi-AI review (`23-REVIEWS.md`, codex HIGH verdict + gemini MEDIUM-1) on 2026-05-29.**

Purpose:
- Close Phase 22's three review-gate residuals (F1 INIT.md doc gap, F2 healthz timeout, F3 SIGTERM trap)
- Close Phase 22's one non-goal (F4 SKILL.md drift test)
- Land the user-requested `withCronMonitor` SDK-composition refactor (F5 **Guarded** Shape A per amended CONTEXT.md D-08)
- Fix migration 0019's "patches everywhere on refuse" behaviour to match migration 0017's atomic-refuse default (D-07, honestly reframed per codex MEDIUM-6)
- Author ADR-0029 IN WAVE 0 (before code) capturing the F5 architectural decision with 5 rejected alternatives (incl. original Shape A) for `/gsd-review` audit

Output:
- 17 tasks across 6 waves (was 17 across 5; Wave 0 added per codex Suggestion 7)
- 14+ modified files across 4 stacks, 1 migration engine, 1 test harness, 1 ADR, SKILL.md + CHANGELOG.md
- 4 new TDD tests (F2 timeout × 4 stacks, F3 sigterm, F4 drift, F5 parity + pre-callback regression × 3 stacks)
- 1 new migration fixture (07-allow-partial-emits-patches)
- 1 new ADR (0029-cron-monitor-sdk-composition.md) authored IN WAVE 0

Revision provenance (codex/gemini review IDs):
- R-rev-1: D-08 Guarded Shape A — codex HIGH-1 → Tasks 2.1/2.2/2.3
- R-rev-2: Split trap design — codex HIGH-2 → Task 3.1
- R-rev-3: F2 per-stack rework — codex MEDIUM-5 + gemini MEDIUM-1 → Tasks 1.4/1.5/1.6/1.7
- R-rev-4: G6 gate replacement — codex MEDIUM-7 → Task 0.1 (harness extension) + Task 5.4 (named-test check)
- R-rev-5: D-07 honest reframe — codex MEDIUM-6 → Tasks 4.1/4.2 + CHANGELOG
- R-rev-6: Supabase Deno seam — codex MEDIUM-4 → Task 2.3
- R-rev-7: ADR-0029 to Wave 0 — codex Suggestion 7 → Task 0.2 (was 5.1)
- R-rev-8: GitNexus per-wave — codex Suggestion 8 → wave-closer tasks
- R-rev-9: Gemini F2 unhandled-rejection (subsumed by R-rev-3) — explicit AbortController + clearTimeout call-out in TS tasks
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/23-observability-followups/CONTEXT.md
@.planning/phases/23-observability-followups/DISCUSSION-LOG.md
@.planning/phases/23-observability-followups/23-REVIEWS.md
@.planning/phases/22-sentry-crons-healthz/CONTEXT.md
@.planning/phases/22-sentry-crons-healthz/PLAN.md
@.planning/phases/22-sentry-crons-healthz/SECURITY.md
@./CLAUDE.md
@./AGENTS.md
@add-observability/templates/ts-cloudflare-worker/cron-monitor.ts
@add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts
@add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts
@add-observability/templates/ts-cloudflare-worker/middleware.ts
@add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts
@add-observability/templates/ts-cloudflare-pages/cron-monitor.ts
@add-observability/templates/ts-supabase-edge/cron-monitor.ts
@add-observability/templates/ts-supabase-edge/cron-monitor.test.ts
@add-observability/templates/go-fly-http/cron_monitor.go
@add-observability/templates/go-fly-http/healthz_snippet.go
@add-observability/init/INIT.md
@add-observability/SKILL.md
@migrations/run-tests.sh
@templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
@templates/.claude/scripts/migrate-0017-axiom-destination.sh
@migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh

<interfaces>
<!-- Key contracts the executor needs. Extract once here to avoid scavenger hunts. -->

From add-observability/templates/ts-cloudflare-worker/cron-monitor.ts (current public surface — PRESERVED under Guarded Shape A):
```typescript
export interface CronMonitorSchedule { type: "crontab" | "interval"; value: string; }
export interface CronMonitorConfig {
  monitorSlug?: string;
  handlerName?: string;
  schedule?: CronMonitorSchedule;
  maxRuntimeSeconds?: number;
}
export function withCronMonitor<E extends Record<string, unknown>>(
  handler: ScheduledFn<E>,
  config?: CronMonitorConfig,
): ScheduledFn<E>;
```

Sentry SDK signature (Context7-verified from getsentry/sentry-javascript, packages/core/src/exports.ts; re-exported by @sentry/cloudflare and @sentry/deno):
```typescript
// withMonitor wraps callback in withIsolationScope and emits in_progress + ok/error checkins with duration tracking.
// IMPORTANT (codex HIGH-1): in_progress check-in fires BEFORE the callback runs. If transport throws there,
// the callback NEVER executes. Guarded Shape A's handlerStarted flag detects this and falls back to unmonitored.
export function withMonitor<T>(
  slug: string,
  callback: () => T,
  monitorConfig?: MonitorConfig
): T;
```

Guarded Shape A target shape (canonical block in CONTEXT.md D-08; executors read from there):
```typescript
let handlerStarted = false;
try {
  await Sentry.withMonitor(
    monitorSlug,
    () => {
      handlerStarted = true;
      return handler(controller, env, ctx);
    },
    monitorConfig,
  );
} catch (err) {
  if (!handlerStarted) {
    // Sentry transport failed before handler ran — fall back to unmonitored.
    await handler(controller, env, ctx);
    return;
  }
  throw err; // handler-thrown OR post-callback errors propagate as before
}
```

From add-observability/templates/go-fly-http/cron_monitor.go (UNCHANGED under D-09 — doc note only):
```go
func WithCronMonitor(ctx context.Context, fn func() error, opts ...CronMonitorOption) error
```

From migrations/run-tests.sh dispatcher (lines 2137-2204 — Wave 0 EXTENDS this):
```bash
# CURRENT: numeric filters only (0001, 0005, ..., 0019) + 2 hardcoded names (preflight, destinations).
# Codex MEDIUM-7: new test names will NOT run unless dispatcher is extended.
if [ -z "$FILTER" ] || [ "$FILTER" = "0001" ]; then test_migration_0001; fi
# ...
if [ -z "$FILTER" ] || [ "$FILTER" = "preflight" ]; then test_preflight_verify_paths; fi
if [ -z "$FILTER" ] || [ "$FILTER" = "destinations" ]; then test_meta_destinations_consistency; fi
```

From templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:42-57 (existing flag parsing):
```bash
ALLOW_PARTIAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --allow-partial) ALLOW_PARTIAL=1; shift ;;
    ...
done
# ALLOW_PARTIAL=1 means "apply clean roots, skip dirty" — D-07 EXTENDS this to also gate clean-root patch emission.
```

From migration 0017's analogue (templates/.claude/scripts/migrate-0017-axiom-destination.sh):
- Migration 0017 ALREADY implements dirty-root-patches-on-refuse (codex MEDIUM-6 verified at line 368). The "0017 = zero-side-effect" framing is WRONG.
- D-07 honest reframe: "default refuse no longer writes to CLEAN roots; DIRTY roots still receive .observability-0019.patch + .gitignore entries for splice recovery."
- Audit Task 4.1 exit condition: 0017 already matches the honest-reframed target. Do NOT escalate to "0017 needs same fix".
</interfaces>
</context>

<gitnexus_required_symbols>
<!-- Per ./CLAUDE.md + codex Suggestion 8: every symbol edit MUST run gitnexus_impact({target, direction: "upstream"}) BEFORE the edit, AND gitnexus_detect_changes() at each WAVE-CLOSER task (not just final Task 5.4). -->

| Task | Symbol | File | Edit shape |
|------|--------|------|------------|
| T-0.1 | run_all / dispatcher block | migrations/run-tests.sh | extend dispatcher to support `test-skill-md-version-matches-latest-migration-to-version` + `test-sigterm-mid-apply-preserves-state` named filters |
| T-0.2 | (ADR file — no symbol) | docs/decisions/0029-cron-monitor-sdk-composition.md | new file; no gitnexus_impact required (file create) |
| T-F2.worker | healthzHandler | add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts | AbortController + setTimeout + 3rd-arg override (Worker supports) |
| T-F2.pages | onRequest | add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts | AbortController + setTimeout + context.env.HEALTHZ_PROBE_TIMEOUT_MS (no 3rd-arg path) |
| T-F2.supabase | healthzHandler | add-observability/templates/ts-supabase-edge/healthz-snippet.ts | AbortController + setTimeout + module-const OR env-var (planner picks; Deno seam constraints apply) |
| T-F2.go | HealthzHandler | add-observability/templates/go-fly-http/healthz_snippet.go | context.WithTimeout (caps handler latency only — explicit code+CHANGELOG note that Get(url) cannot be cancelled) |
| T-F5.worker | withCronMonitor | add-observability/templates/ts-cloudflare-worker/cron-monitor.ts | Guarded Shape A per CONTEXT.md D-08 canonical block |
| T-F5.pages | withCronMonitor | add-observability/templates/ts-cloudflare-pages/cron-monitor.ts | Guarded Shape A |
| T-F5.supabase | withCronMonitor + _setWithMonitorForTest seam | add-observability/templates/ts-supabase-edge/cron-monitor.ts | Guarded Shape A via _setWithMonitorForTest seam (Deno-friendly indirection) |
| T-F3 | engine top-level | templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh | split trap: EXIT (silent idempotent) / INT (cleanup + exit 130) / TERM (cleanup + exit 143); + path-validated `--pause-between-passes` |
| T-F3 | dispatcher | migrations/run-tests.sh | split trap (same shape) at harness level |
| T-D07 | emit_refuse_artifacts | templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:542-573 | gate clean-root emission on `[ "$ALLOW_PARTIAL" -eq 1 ]` |
| T-D09 | WithCronMonitor (Go) | add-observability/templates/go-fly-http/cron_monitor.go | doc-only edit |

Wave-closer gitnexus_detect_changes (per codex Suggestion 8):
- Wave 1 closer: Task 1.7 → run `gitnexus_detect_changes()` after Go healthz
- Wave 2 closer: Task 2.3 → run `gitnexus_detect_changes()` after Supabase F5
- Wave 3 closer: Task 3.1 → run `gitnexus_detect_changes()` after F3 trap
- Wave 4 closer: Task 4.2 → run `gitnexus_detect_changes()` after D-07 0019 fix
- Wave 5 closer: Task 5.4 → existing gitnexus_detect_changes() global gate

Acceptance check on each task: `gitnexus_impact` was run and reported risk level. If HIGH or CRITICAL: action requires explicit "proceed-anyway" rationale in commit body.
</gitnexus_required_symbols>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Cron handler body → Sentry SDK | F5 changes how cron breadcrumbs/scope/user-context flow between invocations via withIsolationScope; **handler-set scope state may not leak to outer capture after isolation unwinds (codex MEDIUM-narrowed semantic)** |
| Outer wrapper (withObservabilityScheduled) → withCronMonitor | F5 Guarded Shape A: POST-callback errors propagate; PRE-callback errors fall back to unmonitored (cron always runs) |
| Healthz handler → probe targets (DB, KV, upstream HTTP) | F2 introduces controlled abort via AbortController + setTimeout/clearTimeout in try/finally (no Promise.race; no unhandled rejections per gemini MEDIUM-1) |
| Migration engine → operator filesystem | F3 split-trap design (EXIT silent / INT exit 130 / TERM exit 143); D-07 honestly reframed: default refuse no longer touches CLEAN roots; DIRTY roots still get .patch + .gitignore for splice recovery |
| Operator interactive shell ↔ engine via SIGINT | F3's INT trap converts "Ctrl-C corrupts state" into "Ctrl-C → cleanup → exit 130" (signal-compatible exit code) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-23-01 | I (Information disclosure) | F5 withCronMonitor + Sentry.withMonitor isolation scope | mitigate | `withIsolationScope` wrapping isolates scope per cron run, preventing leak of one cron's user/tags/breadcrumbs into the next. **REVISED post-review (codex MEDIUM):** the isolation also means handler-set scope state (e.g., `Sentry.setTag` inside the cron body) may NOT be visible to outer error-capture handlers after isolation unwinds. This is documented in CHANGELOG 0.7.0 + ADR-0029 with the precise semantic. ADR-0029 documents this addition. T-F5 tasks assert the addition in the parity tests. |
| T-23-02 | D (Denial of service via unhandled exception → SKIPPED CRON) | F5 outer wrapper chain | mitigate | **REVISED post-review (codex HIGH-1) — NARROWED REGRESSION:** Guarded Shape A restores the "cron always runs" contract that original Shape A regressed. PRE-callback errors (Sentry transport failing on `in_progress`) fall back to unmonitored handler execution via the `handlerStarted` flag. POST-callback errors (Sentry transport failing on `ok`/`error` after handler completed) DO propagate to the outer wrapper. The cron body therefore always executes; only the heartbeat-completion path can fail. T-F5.worker MUST grep middleware.ts `withObservabilityScheduled` to verify it catches post-callback SDK errors so the cron doesn't fail downstream when transport is down post-handler. Acceptance: pre-callback regression test per stack (codex Suggestion 2) MUST pass — "Sentry check-in setup throws before callback start → handler still runs unmonitored, no crash". |
| T-23-03 | I (Information disclosure via timing oracle) | F2 healthz handler | mitigate | **REVISED post-review (codex MEDIUM-5):** per-stack heterogeneous implementation matching each runtime's actual surface — Worker keeps 3rd-arg override (supported); Pages uses `context.env.HEALTHZ_PROBE_TIMEOUT_MS` fallback 2000 (no 3rd-arg path); Supabase uses module-constant OR env-var; Go documents "caps handler latency only, NOT inner Get(url)" honestly. All TS stacks use `AbortController + setTimeout/clearTimeout` in try/finally (per gemini MEDIUM-1 — no Promise.race, no unhandled rejections). Aborted probes report `"timeout"` string sentinel (not boolean false), so attacker cannot fingerprint slow upstreams via latency. Acceptance test per stack: probe hangs > timeout → response within timeout+200ms slack with `{status: "degraded", checks: {<probe>: "timeout"}}`. |
| T-23-04 | D (Denial of service via leaked resources) | F2 aborted probes | mitigate | TS (REVISED per gemini MEDIUM-1): `AbortController + setTimeout` pattern with `try { ... } finally { clearTimeout(timeoutId); }` — timeout always cleaned up regardless of probe outcome; no dangling timer rejections. Go: `db.PingContext(ctx)` honours ctx; for the upstream `Get(url)` probe codex MEDIUM-5 confirmed cannot be cancelled — the `context.WithTimeout` caps handler latency but the underlying outbound call may continue (explicit code comment + CHANGELOG entry per honest-documentation alternative). Test: probe hangs 5s; verify response returns within 2.2s; verify no unhandled rejection logs. |
| T-23-05 | T (Tampering with engine state via signal) | F3 split-trap | mitigate | **REVISED post-review (codex HIGH-2):** split trap design — `EXIT` handler runs cleanup SILENTLY (no warning, no signal re-raise, idempotent — runs on success too without pollution). `INT` handler runs cleanup then `exit 130` (signal-compatible). `TERM` handler runs cleanup then `exit 143` (signal-compatible). Cleanup MUST NOT print env vars, secrets, or partial canonical-file contents to stderr. Test t-sigterm asserts: SIGTERM mid-pass-2 → trap fires → exit code 143 → no half-written canonical file → re-run succeeds → cleanup stderr contains no `SENTRY_DSN=` echoes → trap output ABSENT when test exits 0 normally (silent-on-success acceptance). T-F3 acceptance: `grep -E '(SENTRY_DSN\|API_KEY\|TOKEN)=' <captured_stderr>` returns empty; `grep -q "cleanup" <captured_stderr>` returns empty for normal exits. |
| T-23-06 | E (Elevation of privilege via flag misuse) | D-07 --allow-partial default flip | accept | Operators who relied on R09 "patches everywhere on refuse" must explicitly opt in via `--allow-partial` or `ALLOW_PARTIAL=true`. **REVISED honest framing (codex MEDIUM-6):** CHANGELOG language explicitly states "default refuse no longer writes to CLEAN roots; DIRTY roots still receive .observability-0019.patch + .gitignore entries for splice recovery." NOT "zero-side-effect refuse" — that framing was inaccurate. Migration runbook footnote tells operators with existing automation to add `--allow-partial`. Disposition: ACCEPT — restores the documented "atomic refusal on clean roots" invariant while preserving the dirty-root recovery story. |
| T-23-07 | S (Spoofing via test-only flag in production) | F3 --pause-between-passes flag | mitigate | **REVISED post-review (codex HIGH-2):** path validation REWORKED. Reject any path that doesn't match `${TMPDIR:-/tmp}/sigterm-test-*` (handle unset TMPDIR via `${TMPDIR:-/tmp}` default) OR `migrations/test-fixtures/0019/*/sigterm-*` (explicit fixture allow-list prefix). When present, flag MUST log warning to stderr ("--pause-between-passes is a test-only flag; do not use in production") AND signal file path MUST match one of the two allow-listed prefixes (exit 2 otherwise). The previous formulation `"$TMPDIR"/*` was bypassable when TMPDIR was unset (degenerates to `/*` matching `/etc/passwd`). Acceptance: passing `--pause-between-passes /etc/passwd` exits 2 with "test-only flag with non-allow-listed path"; passing `--pause-between-passes "${TMPDIR:-/tmp}/sigterm-test-xyz"` proceeds; passing with TMPDIR explicitly unset still rejects `/etc/passwd`. |

Severity gating: T-23-02 (D), T-23-04 (D), T-23-05 (T), T-23-07 (S) are MEDIUM (T-23-02 narrowed from HIGH-original-Shape-A to MEDIUM-Guarded-Shape-A). T-23-01 (I) is LOW with the narrowed isolation-scope semantic note. T-23-03 (I) is LOW (post-mitigation). T-23-06 (E) is ACCEPTED. No HIGH or CRITICAL threats remain post-mitigation. Phase proceeds.

### Threat-model deltas vs pre-revision PLAN

- **T-23-02 narrowed:** original Shape A = HIGH (skipped cron); Guarded Shape A = MEDIUM (only heartbeat completion can fail; cron always runs).
- **T-23-07 fixed:** `"$TMPDIR"/*` glob bypassable when TMPDIR unset; replaced with `${TMPDIR:-/tmp}/sigterm-test-*` + fixture-prefix allow-list.
- **T-23-01 narrowed semantic:** `withIsolationScope` is not "purely non-breaking" — documented honest semantic re handler-set scope state.
- **T-23-05 sharpened:** silent-on-success acceptance check added (`grep -q "cleanup" <stderr>` must be empty for exit-0 runs).
</threat_model>

<tasks>

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 0 — REVISION ADDITION (codex Suggestions 7 + MEDIUM-7)             -->
<!-- Pre-implementation harness extension + ADR-0029 authoring               -->
<!-- Both tasks are parallel-safe (different files, no shared state)        -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto">
  <name>Task 0.1 (Wave 0, R-rev-4): migrations/run-tests.sh dispatcher extension for new named filters</name>
  <files>migrations/run-tests.sh</files>
  <read_first>
    - migrations/run-tests.sh lines 2133-2204 (the existing dispatcher — numeric filters + `preflight` + `destinations` hardcoded names)
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex MEDIUM-7 (the harness-extension blocker)
    - .planning/phases/23-observability-followups/CONTEXT.md D-05 (signal-file flag spec) + D-06 (test name + location)
  </read_first>
  <action>
    Per codex MEDIUM-7: extend the dispatcher in `migrations/run-tests.sh` to support the two new named filters BEFORE Tasks 1.3 + 3.1 add the test functions. Without this extension, `migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version` and `migrations/run-tests.sh test-sigterm-mid-apply-preserves-state` will be silently no-ops.

    [BLOCKING] Run `gitnexus_impact({target: "run_all", direction: "upstream"})` BEFORE editing; record risk in commit body.

    **Edit lines 2197-2204** (end of dispatcher, after `destinations` hardcoded name), add TWO new dispatcher entries (kebab-case CLI names matching D-06's convention):

    ```bash
    if [ -z "$FILTER" ] || [ "$FILTER" = "test-skill-md-version-matches-latest-migration-to-version" ]; then
      # Function exists after Task 1.3 lands. Guard with declare -F so this commit doesn't
      # try to run it before Task 1.3 defines it.
      if declare -F test_skill_md_version_matches_latest_migration_to_version >/dev/null 2>&1; then
        test_skill_md_version_matches_latest_migration_to_version
      fi
    fi

    if [ -z "$FILTER" ] || [ "$FILTER" = "test-sigterm-mid-apply-preserves-state" ]; then
      if declare -F test_sigterm_mid_apply_preserves_state >/dev/null 2>&1; then
        test_sigterm_mid_apply_preserves_state
      fi
    fi
    ```

    The `declare -F` guard makes this commit safely standalone: dispatching to a not-yet-defined function silently skips, so the harness stays green between Wave 0 and Wave 1/Wave 3.

    Commit: `feat(23): Wave 0 — extend migrations/run-tests.sh dispatcher for new named filters (R-rev-4)`. Commit body MUST cite codex MEDIUM-7 + the two CLI names being added.
  </action>
  <verify>
    <automated>
      grep -q 'FILTER" = "test-skill-md-version-matches-latest-migration-to-version"' migrations/run-tests.sh &&
      grep -q 'FILTER" = "test-sigterm-mid-apply-preserves-state"' migrations/run-tests.sh &&
      grep -q 'declare -F test_skill_md_version_matches_latest_migration_to_version' migrations/run-tests.sh &&
      bash migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version  # exits 0 (no-op until Task 1.3)
    </automated>
  </verify>
  <done>Dispatcher extended; both new CLI names route to declare -F guarded function calls. Harness still passes (guarded functions skip silently).</done>
  <acceptance_criteria>
    - Two new dispatcher entries present with declare -F guards
    - `bash migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version` exits 0 (no-op skip)
    - `bash migrations/run-tests.sh test-sigterm-mid-apply-preserves-state` exits 0 (no-op skip)
    - Full harness `bash migrations/run-tests.sh` still passes — no regressions
    - gitnexus_impact run on `run_all`; risk recorded
    - Commit: `feat(23): Wave 0 — extend migrations/run-tests.sh dispatcher for new named filters (R-rev-4)`
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 0.2 (Wave 0, R-rev-7): Author ADR-0029 (cron-monitor SDK composition — Guarded Shape A) BEFORE code</name>
  <files>docs/decisions/0029-cron-monitor-sdk-composition.md</files>
  <read_first>
    - .planning/phases/23-observability-followups/CONTEXT.md §D-08 (AMENDED — Guarded Shape A canonical block)
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex HIGH-1 (the empirical evidence for why Guarded beats original)
    - .planning/phases/23-observability-followups/DISCUSSION-LOG.md §"Post-review revision — D-08 Guarded Shape A" (lines 182-212)
    - .planning/phases/23-observability-followups/CONTEXT.md §"Discussion log" OQ-8 (original 5 shapes A/B/C/D/F with rationales)
    - docs/decisions/0028-sentry-crons-healthz-conventions.md (template for ADR shape + tone)
    - docs/decisions/0027-postphase-observability-hook.md (short ADR template)
  </read_first>
  <action>
    **Per codex Suggestion 7: ADR-0029 lands in WAVE 0 (was Wave 5), so reviewers + future maintainers see the architectural rationale BEFORE the F5 code lands.** This task is parallel-safe with Task 0.1 (different files) and is a `depends_on` for Tasks 2.1/2.2/2.3 (the ADR locks the Guarded Shape A contract those tasks implement).

    Author `docs/decisions/0029-cron-monitor-sdk-composition.md` with these required sections:

    **# 0029 — cron-monitor SDK composition (Guarded Shape A)**
    Status: Accepted
    Date: 2026-05-29
    Phase: 23-observability-followups
    Supersedes: none (extends 0028's cron-monitor conventions)
    Revision: amended post-multi-AI-review on 2026-05-29 from original Shape A to Guarded Shape A per `23-REVIEWS.md` codex HIGH-1.

    **## Context**
    Phase 22 reinvented Sentry's in_progress→ok/error lifecycle (duration tracking, thenable handling) around a 3-source slug-resolution wrapper. `Sentry.withMonitor<T>(slug, callback, monitorConfig?): T` ships in `@sentry/core` and is re-exported by `@sentry/cloudflare` + `@sentry/deno`. Post-PR-#53 the user requested a refactor to compose with the SDK helper rather than reinvent the lifecycle. Six honest shapes considered (5 rejected).

    **## Decision**
    **Guarded Shape A** — compose `Sentry.withMonitor` underneath our existing outer wrapper, with a `handlerStarted` flag inside the callback. If `Sentry.withMonitor` throws BEFORE the callback runs (e.g., transport failure on `in_progress` check-in), fall back to running the handler unmonitored. If it throws AFTER the callback completed (post-handler transport failure), let the error propagate.

    Canonical code block (binding for executors — also in CONTEXT.md D-08):

    ```typescript
    let handlerStarted = false;
    try {
      await Sentry.withMonitor(
        monitorSlug,
        () => {
          handlerStarted = true;
          return handler(controller, env, ctx);
        },
        monitorConfig,
      );
    } catch (err) {
      if (!handlerStarted) {
        // Sentry transport failed before handler ran — fall back to unmonitored.
        await handler(controller, env, ctx);
        return;
      }
      throw err; // handler-thrown OR post-callback errors propagate as before
    }
    ```

    **## Alternatives Rejected**

    | Shape | Description | Why rejected |
    |-------|-------------|--------------|
    | **Original Shape A (unguarded)** | `await Sentry.withMonitor(slug, () => handler(...), monitorConfig);` with no handlerStarted flag | **Codex HIGH-1 empirical finding (`23-REVIEWS.md`):** `withMonitor` sends `in_progress` check-in BEFORE invoking the callback (verified at `@sentry/core/src/exports.ts`). Transport failure at that moment causes the **cron handler to be SKIPPED ENTIRELY**, not just the heartbeat logging. On Cloudflare Pages there is no outer observability wrapper at all, so this failure goes straight to the external caller. On Worker/Supabase the outer wrapper catches the throw but the job body is still skipped. This regression is materially worse than the original PLAN's "SDK errors now bubble up" framing. Guarded variant restores the "cron always runs" contract. |
    | B (Drop-in replacement) | `withCronMonitor(handler, config?) = (c, e, ctx) => Sentry.withMonitor(resolveSlug(...), () => handler(c, e, ctx), buildMonitorConfig(config))` | Drops R02 fail-safe (Sentry logs warning on no-DSN). Drops R04 swallow. Loses D6's silent-on-no-DSN behaviour. Also subject to original-Shape-A skipped-cron regression. |
    | C (Deprecate + parallel `withCronMonitorV2`) | Keep v0.6.0 wrapper with `@deprecated`; add `withCronMonitorV2` as Shape A | +50 LOC per file. Zero downstream risk but compounds future maintenance — two wrappers to keep in sync. |
    | D (Compose with SDK-throw firewall via stack inspection) | Shape A + try/catch wrapper that catches errors whose stack frame includes `captureCheckIn` | Restores R02/R04 at significant complexity cost. Brittle stack-frame inspection. High test surface. Subsumed by Guarded Shape A which achieves the cron-always-runs goal more reliably. |
    | F (No refactor — port only `duration` tracking pattern) | +8 LOC per file. All Phase 22 contracts preserved. | Loses strategic value of using upstream's primitive. User's "baked in" directive interpreted as a genuine refactor. |

    **## Consequences**

    **Preserved contracts (Phase 22):** D6 (3-source slug resolution), R02 fail-safe no-DSN (preserved at the if-isConfigured guard at line 138), D11 (multi-cron explicit-slug), D12 (monitorConfig 2nd-arg forwarding shape), **AND the "cron always runs" guarantee** that original Shape A regressed.

    **Documented regression (NARROWED vs original Shape A):** R02/R04 SDK-error swallow drops only for POST-callback errors — i.e., errors from the `ok`/`error` check-ins after the handler completed. PRE-callback errors no longer skip the cron (Guarded fallback runs handler unmonitored). POST-callback errors propagate to the outer `withObservabilityScheduled` capture path. Operators see SDK transport failures in their normal error-capture path instead of silent swallow ONLY when the handler already completed successfully. `SENTRY_DEBUG=1` is no longer the surfacing mechanism for SDK errors.

    **Documented addition (HONEST SEMANTIC per codex MEDIUM):** `withIsolationScope` wrapping. Each cron run gets its own Sentry scope. This is NOT "purely non-breaking correctness improvement" as original PLAN claimed — handler-set scope state (e.g., `Sentry.setTag`, `Sentry.setUser`, breadcrumbs set inside the cron body) may NOT be visible to outer error-capture handlers after isolation unwinds. Downstream consumers relying on cron-body scope mutations becoming visible to outer error handlers will see different behaviour. Tags/breadcrumbs/user-context still no longer leak BETWEEN consecutive cron invocations (the original benefit).

    **Downstream impact:** fxsa and callbot pull `add-observability 0.7.0` → see the narrowed regression + honest isolation-scope addition. CHANGELOG.md 0.7.0 calls both out explicitly. No code change required downstream unless they relied on the documented behaviours.

    **Go stack unchanged.** `sentry-go` ships no `WithMonitor` equivalent (Context7-verified). The Go `WithCronMonitor` impl IS the cross-stack parity. See D-09 / `cron_monitor.go` package-doc note.

    **## Empirical evidence supporting Guarded variant**

    From `23-REVIEWS.md` §Codex HIGH-1: read-only codebase exploration verified `@sentry/core` `withMonitor` at `packages/core/src/exports.ts` sends `in_progress` check-in via `captureCheckIn` BEFORE invoking the callback. The Cloudflare Pages template (`add-observability/templates/ts-cloudflare-pages/cron-monitor.ts:115`) has NO outer observability wrapper — a `captureCheckIn` failure would propagate directly to the external caller, with the cron body never executing. This empirical finding (not visible to prompt-only Gemini review) drove the Guarded amendment.

    **## Links**
    - CONTEXT (amended): `.planning/phases/23-observability-followups/CONTEXT.md` §D-08 (Guarded canonical block)
    - Reviews: `.planning/phases/23-observability-followups/23-REVIEWS.md` §Codex HIGH-1
    - Discussion log: `.planning/phases/23-observability-followups/DISCUSSION-LOG.md` §"Post-review revision — D-08 Guarded Shape A"
    - Implementation: this phase's Task 2.1 / 2.2 / 2.3 GREEN commits
    - Phase 22 contracts: `.planning/phases/22-sentry-crons-healthz/PLAN.md` §R02 §R04, `…/CONTEXT.md` §D6 §D11 §D12
    - SDK reference: `@sentry/cloudflare` re-export of `@sentry/core` `withMonitor<T>` in `packages/core/src/exports.ts`

    Commit: `docs(23): Wave 0 — ADR-0029 cron-monitor SDK composition (Guarded Shape A) — R-rev-7`.
  </action>
  <verify>
    <automated>
      test -f docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "^# 0029" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "Guarded Shape A" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "Alternatives Rejected" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "Original Shape A (unguarded)" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "withIsolationScope" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "POST-callback" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "PRE-callback" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "handlerStarted" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -E "Shape B|\\| B" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -E "Shape C|\\| C" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -E "Shape D|\\| D" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -E "Shape F|\\| F" docs/decisions/0029-cron-monitor-sdk-composition.md
    </automated>
  </verify>
  <done>ADR-0029 authored in Wave 0 with all 5 rejected shapes (incl. original Shape A) + Codex's pre-callback-throw empirical evidence + narrowed regression semantics + honest isolation-scope addition. Ready for executors in Wave 2 to consume.</done>
  <acceptance_criteria>
    - File exists at docs/decisions/0029-cron-monitor-sdk-composition.md
    - Headers: Context / Decision / Alternatives Rejected / Consequences / Empirical evidence / Links present
    - All 5 rejected shapes (Original-Shape-A unguarded, B, C, D, F) appear with their rejection rationale
    - The canonical handlerStarted code block is reproduced (binding for executors)
    - The narrowed R02/R04 regression (post-callback only) and honest withIsolationScope semantic (scope state may not leak to outer capture) are spelled out
    - Codex HIGH-1 empirical evidence section present
    - Commit: `docs(23): Wave 0 — ADR-0029 cron-monitor SDK composition (Guarded Shape A) — R-rev-7`
  </acceptance_criteria>
</task>


<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 1 — parallel-safe; independent files, no shared state              -->
<!-- depends_on: Task 0.1 (Task 1.3 needs dispatcher extension)              -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto">
  <name>Task 1.1 (Wave 1, F1): INIT.md per-stack Phase 5 composition notes</name>
  <files>add-observability/init/INIT.md</files>
  <depends_on>none</depends_on>
  <read_first>
    - add-observability/init/INIT.md lines 282-389 (existing Phase 5 per-stack subsections; F1 lands inside each)
    - .planning/phases/23-observability-followups/CONTEXT.md §"Resolved decisions" D-02 (batch) and §"Goals" G1
    - .planning/phases/22-sentry-crons-healthz/CONTEXT.md (D5a, D5b, D5d composition order for the 4 stacks — F1 cites these)
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts (target of file:line link from the worker subsection)
    - add-observability/templates/go-fly-http/cron_monitor.go (target of file:line link from the go subsection)
  </read_first>
  <action>
    Per D-02 + G1: add a ≤5-line `withCronMonitor` composition paragraph to each of the 4 Phase 5 per-stack subsections in `add-observability/init/INIT.md` (worker, pages, supabase-edge, go). The react-vite subsection at the equivalent location stays UNCHANGED.

    For each of the 4 stacks, the paragraph MUST:
    1. Cite `withCronMonitor` (the wrapper that ships in cron-monitor.{ts,go})
    2. Cite the Phase 22 composition-order decision: D5a (worker), D5a (pages — same shape), D5b (supabase-edge), D5d (go)
    3. Link to the wrapper source file with a relative file:line link of the form `templates/{stack}/cron-monitor.{ts,go}:<line-of-withCronMonitor-export>`

    Concrete substrings to insert per stack (paraphrase allowed for prose flow, but the literal references MUST appear verbatim):

    - **ts-cloudflare-worker** (insert at end of subsection "Phase 5 detail — `ts-cloudflare-worker`"):
      "**Scheduled handler — `withCronMonitor` composition.** Per Phase 22 D5a, `withCronMonitor` composes INNERMOST: `withSentry(env)(withObservabilityScheduled(withCronMonitor(handler, {...})))`. See `templates/ts-cloudflare-worker/cron-monitor.ts:133` for the exported wrapper signature."

    - **ts-cloudflare-pages** (insert at the equivalent location):
      "**Scheduled handler — `withCronMonitor` composition.** Per Phase 22 D5a (Pages mirrors Worker), `withCronMonitor` composes INNERMOST when the Pages function exports a `scheduled` handler. See `templates/ts-cloudflare-pages/cron-monitor.ts:<line>` for the exported wrapper signature."

    - **ts-supabase-edge** (insert at the equivalent location):
      "**Scheduled handler — `withCronMonitor` composition.** Per Phase 22 D5b (supabase-edge composition order), `withCronMonitor` composes INNERMOST under `withObservability`. See `templates/ts-supabase-edge/cron-monitor.ts:<line>` for the exported wrapper signature."

    - **go-fly-http** (insert at the equivalent location):
      "**Scheduled handler — `WithCronMonitor` composition.** Per Phase 22 D5d, `WithCronMonitor` composes INNERMOST in the middleware chain. See `templates/go-fly-http/cron_monitor.go:225` for the exported wrapper signature. NOTE (D-09): `sentry-go` ships no `WithMonitor` equivalent — this impl IS the cross-stack parity for that helper."

    Resolve `<line>` literals by `grep -n "^export function withCronMonitor\\|^func WithCronMonitor" <target-file>` at edit time; use that line number.

    react-vite Phase 5 subsection: explicitly verify NO changes (browser stack has no cron concept).
  </action>
  <verify>
    <automated>
      grep -c "withCronMonitor\\|WithCronMonitor" add-observability/init/INIT.md | awk '$1 >= 4 { exit 0 } { exit 1 }' &&
      grep -q "templates/ts-cloudflare-worker/cron-monitor.ts:" add-observability/init/INIT.md &&
      grep -q "templates/ts-cloudflare-pages/cron-monitor.ts:" add-observability/init/INIT.md &&
      grep -q "templates/ts-supabase-edge/cron-monitor.ts:" add-observability/init/INIT.md &&
      grep -q "templates/go-fly-http/cron_monitor.go:" add-observability/init/INIT.md
    </automated>
  </verify>
  <done>INIT.md Phase 5 has 4 stack subsections each citing withCronMonitor with a templates/{stack}/cron-monitor.{ts,go}:<line> link; react-vite subsection unchanged.</done>
  <acceptance_criteria>
    - grep returns ≥ 4 occurrences of `withCronMonitor`/`WithCronMonitor` in INIT.md (one per stack minimum)
    - Each of the 4 worker/pages/supabase-edge/go subsections contains a file:line link to its cron-monitor wrapper file
    - react-vite subsection diff is empty (compare git diff for that subsection only)
    - gitnexus_impact NOT required (doc-only edit, no code symbol modified)
    - Commit: `docs(23): F1 INIT.md per-stack Phase 5 withCronMonitor composition notes`
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 1.2 (Wave 1, D-09): Go cron_monitor.go SDK-gap doc note</name>
  <files>add-observability/templates/go-fly-http/cron_monitor.go</files>
  <depends_on>none</depends_on>
  <read_first>
    - add-observability/templates/go-fly-http/cron_monitor.go lines 1-32 (existing package doc — D-09 note appends to this)
    - .planning/phases/23-observability-followups/CONTEXT.md D-09 (Go SDK gap is documented, not upstream-fixed)
    - .planning/phases/23-observability-followups/CONTEXT.md G8 (≤5-line note explaining sentry-go ships no WithMonitor equivalent)
  </read_first>
  <action>
    Per D-09 + G8: append a ≤5-line note to the package doc of `add-observability/templates/go-fly-http/cron_monitor.go` (the comment block lines 1-32) explaining that `sentry-go` ships no `WithMonitor` equivalent and this impl IS the cross-stack parity for that helper.

    Insert the following note immediately before line 23 (`package {{PACKAGE_NAME}}`), as the LAST paragraph of the existing package-doc comment block:

    ```go
    // SDK gap (D-09 / Phase 23): unlike `@sentry/javascript`'s `Sentry.withMonitor`,
    // `sentry-go` ships no `WithMonitor` equivalent — only the lower-level
    // `CaptureCheckIn`. This `WithCronMonitor` IS the cross-stack parity for the
    // missing helper. If a future `sentry-go` release adds `WithMonitor`, this
    // impl can be slimmed to a composition; see `docs/decisions/0029-cron-monitor-sdk-composition.md`.
    ```

    Symbol body (`WithCronMonitor` function body lines 225-270) MUST remain untouched. The edit is comment-only — but per ./CLAUDE.md, gitnexus_impact is still required because the doc immediately precedes the symbol.

    [BLOCKING] Run `gitnexus_impact({target: "WithCronMonitor", direction: "upstream"})` before the edit; record risk level in the commit body.
  </action>
  <verify>
    <automated>
      grep -q "SDK gap (D-09" add-observability/templates/go-fly-http/cron_monitor.go &&
      grep -q "sentry-go.*no.*WithMonitor" add-observability/templates/go-fly-http/cron_monitor.go
    </automated>
  </verify>
  <done>Package doc block contains the ≤5-line D-09 note immediately before the package declaration; function body unchanged.</done>
  <acceptance_criteria>
    - The literal phrase "SDK gap (D-09" appears in the file
    - The phrase "sentry-go" appears with "no" and "WithMonitor" near it
    - `WithCronMonitor` function body byte-identical to HEAD (verified via git diff of that line range)
    - gitnexus_impact was run; report risk level (likely LOW for doc-only edit)
    - Commit: `docs(23): D-09 document sentry-go WithMonitor SDK gap in cron_monitor.go`
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 1.3 (Wave 1, F4): SKILL.md drift test (TDD red-green)</name>
  <files>migrations/run-tests.sh, skill/SKILL.md (temporarily for RED)</files>
  <depends_on>Task 0.1 (dispatcher extension — without this, the new named filter is a no-op)</depends_on>
  <read_first>
    - migrations/run-tests.sh (full file — Wave 0 already extended the dispatcher; this task adds the function body)
    - skill/SKILL.md lines 1-15 (frontmatter format that D-04's parser targets)
    - migrations/0019-sentry-crons-and-healthz.md lines 1-10 (frontmatter format showing `to_version:` field)
    - .planning/phases/23-observability-followups/CONTEXT.md D-04 (minimal bash parser, no yq) and D-06 (test lives in run-tests.sh) and G4
  </read_first>
  <behavior>
    Per D-06, add a new test function in `migrations/run-tests.sh` named exactly: `test-skill-md-version-matches-latest-migration-to-version` (kebab-case CLI; bash function `test_skill_md_version_matches_latest_migration_to_version`).

    The test:
    1. Extracts `skill/SKILL.md` version using D-04's minimal parser: `grep ^version: skill/SKILL.md | awk '{print $2}'`
    2. Finds the highest-numbered file in `migrations/` matching `[0-9][0-9][0-9][0-9]-*.md` (use `ls migrations/[0-9][0-9][0-9][0-9]-*.md | sort | tail -1`)
    3. Extracts that file's `to_version:` field using the SAME parser: `grep ^to_version: <file> | awk '{print $2}'`
    4. Asserts equality; on mismatch, prints `FAIL: SKILL.md at vX.Y.Z but migration NNNN declares to_version: vA.B.C` and increments FAIL

    Add an inline comment in the function body acknowledging the parser's deliberate minimalism (per gemini LOW concern + D-04):
    ```bash
    # NOTE (D-04): intentionally minimal grep + awk parser. Fragile against
    # YAML variations (quoted values, indented keys, trailing comments).
    # SKILL.md frontmatter is fixed-shape (`version: X.Y.Z` on its own line);
    # if that ever changes, this test must be updated.
    ```

    RED phase: temporarily desync skill/SKILL.md to version `1.99.0`; run `migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version`; assert exit code ≠ 0 and stderr contains the FAIL message.

    GREEN phase: restore skill/SKILL.md version; run the same command; assert exit code 0 and stdout contains `PASS: test-skill-md-version-matches-latest-migration-to-version`.
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "run_all", direction: "upstream"})` on migrations/run-tests.sh's test runner; record risk.

    **RED commit** (commit message `test(23): F4 SKILL.md drift test — RED`):
    1. Add the bash function `test_skill_md_version_matches_latest_migration_to_version` to migrations/run-tests.sh. The function MUST:
       - Use only `grep`, `awk`, `ls`, `sort`, `tail` (no `yq`, no `python`, no `jq`)
       - Include the D-04 minimalism comment block (above)
       - Print exactly `FAIL: SKILL.md at v<skill_version> but migration <NNNN> declares to_version: v<migration_version>` on mismatch
       - Increment global `FAIL` counter and use the same PASS/FAIL/SKIP color scheme as sibling tests
       - The dispatcher entry for this function already exists (added by Task 0.1) — Task 1.3 just adds the function body, which the `declare -F` guard then sees and invokes.
    2. Temporarily edit skill/SKILL.md line 3 from `version: 1.18.0` to `version: 1.99.0` (RED state — DO NOT commit this skill/SKILL.md edit)
    3. Run `migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version 2>&1 | tee /tmp/red-output.txt`
    4. Assert: exit code is non-zero AND `grep -q "FAIL: SKILL.md at v1.99.0 but migration .* declares to_version: v1.18.0" /tmp/red-output.txt`
    5. Revert skill/SKILL.md to `version: 1.18.0`
    6. Commit migrations/run-tests.sh changes ONLY

    **GREEN commit** (commit message `feat(23): F4 SKILL.md drift test passes against current versions — GREEN`):
    1. Run `migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version 2>&1 | tee /tmp/green-output.txt`
    2. Assert: exit code 0 AND `grep -q "PASS.*test-skill-md-version-matches-latest-migration-to-version" /tmp/green-output.txt`
    3. Commit message body MUST document: "RED→GREEN pair for D-06 / G4. Parser per D-04: grep + awk only, no yq dep. Depends on Task 0.1 dispatcher extension (R-rev-4)."
    4. May be `--allow-empty` if RED commit already left tests passing.
  </action>
  <verify>
    <automated>
      bash migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version &&
      grep -q "test_skill_md_version_matches_latest_migration_to_version" migrations/run-tests.sh &&
      grep -q "NOTE (D-04): intentionally minimal" migrations/run-tests.sh &&
      ! grep -q "yq " migrations/run-tests.sh
    </automated>
  </verify>
  <done>RED commit pushed test, ran against desynced SKILL.md, captured FAIL message. GREEN commit ran against current SKILL.md and passes. Test uses only grep + awk; no yq. D-04 minimalism comment present.</done>
  <acceptance_criteria>
    - Test function name in bash: `test_skill_md_version_matches_latest_migration_to_version` (greppable)
    - Filter name (CLI arg): `test-skill-md-version-matches-latest-migration-to-version` (kebab-case)
    - `grep -E "yq |yq\\$" migrations/run-tests.sh` returns no new occurrences (D-04 compliance)
    - D-04 minimalism comment block present in function body (gemini LOW concern addressed)
    - RED commit log shows the test failed with the documented FAIL message when SKILL.md was desynced
    - GREEN commit log shows the test passing
    - Dispatcher entry from Task 0.1 now invokes the function (declare -F guard sees it)
    - gitnexus_impact run on `run_all`; risk level recorded
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 1.4 (Wave 1, F2.worker): healthz per-probe timeout — TS Cloudflare Worker (TDD) — R-rev-3 + R-rev-9</name>
  <files>add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts, add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts</files>
  <depends_on>none</depends_on>
  <read_first>
    - add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts (full file — F2 wraps each probe; preserve R06 fail-closed)
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts (existing test conventions — vitest, vi.mock, fakeController pattern)
    - .planning/phases/23-observability-followups/CONTEXT.md D-03 (REVISED post-review: per-stack heterogeneity — Worker keeps 3rd-arg override; Pages uses env var; Supabase uses module-const or env-var; Go documents timeout-caps-handler-only)
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex MEDIUM-5 + §Gemini MEDIUM-1 (per-stack rework + AbortController + clearTimeout pattern)
    - .planning/phases/22-sentry-crons-healthz/SECURITY.md §S4
  </read_first>
  <behavior>
    **Per codex MEDIUM-5 — Worker keeps current shape (it ACTUALLY supports the 3rd-arg override).** No D-03 narrowing applies to Worker.

    Test cases for healthz-snippet.test.ts (new file):

    - **Test 1 (RED first)**: probe that resolves quickly (10ms) → returns `{status: "ok", checks: {kv: true}}` within timeout. Asserts the happy path is unchanged.
    - **Test 2 (RED first)**: probe that hangs > 2000ms → response returns within 2200ms (2000ms timeout + 200ms slack) with `{status: "degraded", checks: {kv: "timeout"}}` — `"timeout"` is a STRING (not boolean false).
    - **Test 3 (RED first)**: caller passes a custom timeout via `healthzHandler(req, env, { probeTimeoutMs: 500 })` — probe hanging 1000ms aborts at 500ms.
    - **Test 4**: pre-existing behaviour — handler keeps R06 (zero-probes-configured → 503 + reason).
    - **Test 5 (RED first — gemini MEDIUM-1)**: after a fast probe (10ms) completes, no unhandled-rejection warning is emitted (verify via `process.on('unhandledRejection')` listener installed by the test setup). Asserts AbortController + clearTimeout pattern correctly tears down the timer.

    Test handler probe shape must use `vi.fn` mocks that accept `AbortSignal` and respect abort.
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "healthzHandler", direction: "upstream"})` on the worker healthz-snippet; record risk.

    **RED commit** (`test(23): F2 worker healthz per-probe timeout — RED`):
    1. Create `add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts` following the vitest pattern from cron-monitor.test.ts:
       - `import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";`
       - `import { healthzHandler } from "./healthz-snippet";`
       - 5 tests per `<behavior>` block above
       - Use `AbortSignal` in mocks; test 2's hanging probe uses `new Promise((_resolve, reject) => signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))))`
       - Test 5 installs `process.on('unhandledRejection', listener)` in beforeEach, removes in afterEach; asserts listener was never called.
    2. Run `cd add-observability/templates/ts-cloudflare-worker && npx vitest run healthz-snippet.test.ts 2>&1 | tee /tmp/red-f2-worker.txt`
    3. Assert: tests 2, 3, 5 FAIL.
    4. Commit test file ONLY.

    **GREEN commit** (`feat(23): F2 worker healthz per-probe timeout — AbortController + clearTimeout (R-rev-9) — GREEN`):
    1. Modify `add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts`:
       a. Add an exported constant at top of file:
          ```typescript
          /** D-03 default per-probe timeout in ms; override via healthzHandler 3rd arg. */
          export const DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000;
          ```
       b. Add optional 3rd parameter to `healthzHandler` (Worker keeps this shape per codex MEDIUM-5):
          ```typescript
          export async function healthzHandler(
            _req: Request,
            env: HealthzEnv,
            opts?: { probeTimeoutMs?: number },
          ): Promise<Response>
          ```
       c. Inside the function, replace `const checks: Record<string, boolean> = {};` with `const checks: Record<string, boolean | "timeout"> = {};`
       d. Compute `const probeTimeoutMs = opts?.probeTimeoutMs ?? DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS;`
       e. **Per gemini MEDIUM-1: AbortController + setTimeout + try/finally pattern** (NOT Promise.race + abort-rejection):
          ```typescript
          if (env.OBSERVABILITY_KV) {
            const controller = new AbortController();
            const timeoutId = setTimeout(
              () => controller.abort(new DOMException("probe timeout", "TimeoutError")),
              probeTimeoutMs,
            );
            try {
              // KV doesn't accept AbortSignal — wrap in a controller-watching race.
              await new Promise<void>((resolve, reject) => {
                controller.signal.addEventListener("abort", () =>
                  reject(new DOMException("aborted", "TimeoutError")),
                );
                env.OBSERVABILITY_KV!.get("healthz-probe")
                  .then(() => resolve())
                  .catch(reject);
              });
              checks.kv = true;
            } catch (e) {
              checks.kv = (e instanceof DOMException && e.name === "TimeoutError") ? "timeout" : false;
            } finally {
              clearTimeout(timeoutId);
            }
          }
          ```
          For SERVICE_BINDING probe, fetch accepts `signal` directly — pass `controller.signal` to `new Request("https://internal/healthz", { signal: controller.signal })`. Same try/finally + clearTimeout shape.
       f. Update `allOk = probeNames.every((k) => checks[k] === true);`
    2. Run `npx vitest run healthz-snippet.test.ts 2>&1 | tee /tmp/green-f2-worker.txt`
    3. Assert: ALL 5 tests pass.
    4. Commit production file.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-cloudflare-worker && npx vitest run healthz-snippet.test.ts &&
      grep -q "DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000" add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts &&
      grep -q "new AbortController" add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts &&
      grep -q "clearTimeout" add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts &&
      grep -q '"timeout"' add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts &&
      ! grep -q "Promise.race" add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts  # gemini MEDIUM-1: NO Promise.race + reject
    </automated>
  </verify>
  <done>RED→GREEN pair; AbortController + setTimeout + try/finally + clearTimeout pattern; no unhandled rejections; 3rd-arg override preserved (Worker has the runtime support per codex MEDIUM-5).</done>
  <acceptance_criteria>
    - vitest reports 5/5 tests passing
    - File contains `AbortController`, `clearTimeout`, `"timeout"` sentinel
    - File does NOT contain `Promise.race` with abort-rejection (gemini MEDIUM-1 compliance)
    - 3rd-arg override `opts?: { probeTimeoutMs?: number }` present
    - R06 fail-closed path still passes
    - gitnexus_impact recorded
  </acceptance_criteria>
</task>


<task type="auto" tdd="true">
  <name>Task 1.5 (Wave 1, F2.pages): healthz per-probe timeout — TS Cloudflare Pages (TDD) — R-rev-3 NARROWED</name>
  <files>add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts, add-observability/templates/ts-cloudflare-pages/healthz-snippet.test.ts</files>
  <depends_on>none</depends_on>
  <read_first>
    - add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts (the file being modified — line 24 is the onRequest signature)
    - add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts (just-edited reference — pages cannot mirror the 3rd-arg pattern)
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex MEDIUM-5 (Pages has NO 3rd-arg path — onRequest signature is runtime-fixed)
    - .planning/phases/23-observability-followups/CONTEXT.md D-03 (REVISED post-review: per-stack heterogeneity)
  </read_first>
  <behavior>
    **Per codex MEDIUM-5: Pages exports a runtime-fixed `onRequest(context)` — the third-arg override IS NOT a real operator-facing path.** D-03 is narrowed for Pages: configurable via `context.env.HEALTHZ_PROBE_TIMEOUT_MS` env var (fallback to module-level `DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000`). Operators set the env var on the Pages project.

    Test cases (mirror Task 1.4 with Pages-specific adjustments):

    - **Test 1**: fast probe → ok within timeout
    - **Test 2**: hanging probe → `{status: "degraded", checks: {<probe>: "timeout"}}` within 2.2s
    - **Test 3 (REVISED — env var instead of 3rd arg)**: caller sets `context.env.HEALTHZ_PROBE_TIMEOUT_MS = "500"` — probe hanging 1000ms aborts at 500ms
    - **Test 4**: R06 fail-closed preserved
    - **Test 5 (gemini MEDIUM-1)**: no unhandled rejection after fast probe
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "onRequest", direction: "upstream"})` on the Pages healthz-snippet; record risk.

    **RED commit** (`test(23): F2 pages healthz per-probe timeout — RED`):
    Mirror Task 1.4 test structure but for Test 3: build the test context with `env.HEALTHZ_PROBE_TIMEOUT_MS = "500"` instead of passing a 3rd arg.

    **GREEN commit** (`feat(23): F2 pages healthz per-probe timeout — context.env-driven (R-rev-3 narrowed) — GREEN`):
    1. Modify `add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts`:
       a. Add module-level constant:
          ```typescript
          /** D-03 default per-probe timeout in ms. Override via context.env.HEALTHZ_PROBE_TIMEOUT_MS. */
          export const DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000;
          ```
       b. **Per codex MEDIUM-5: DO NOT add a third onRequest arg** — onRequest signature is runtime-fixed by Pages. Instead, inside the handler body:
          ```typescript
          const probeTimeoutMs = Number(context.env.HEALTHZ_PROBE_TIMEOUT_MS) || DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS;
          ```
          Add an inline comment acknowledging the narrowing:
          ```typescript
          // D-03 (narrowed for Pages per codex MEDIUM-5): onRequest signature is runtime-fixed —
          // operators configure timeout via env var, not function args. Worker keeps the 3rd-arg path.
          ```
       c. Apply the same AbortController + setTimeout + try/finally + clearTimeout pattern from Task 1.4 to each probe.
       d. `checks: Record<string, boolean | "timeout">` shape; `"timeout"` sentinel.
    2. Run `npx vitest run healthz-snippet.test.ts`. Assert 5/5 pass.
    3. Commit.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-cloudflare-pages && npx vitest run healthz-snippet.test.ts &&
      grep -q "DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000" add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts &&
      grep -q "context.env.HEALTHZ_PROBE_TIMEOUT_MS" add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts &&
      grep -q "narrowed for Pages per codex MEDIUM-5" add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts &&
      grep -q "new AbortController" add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts &&
      grep -q "clearTimeout" add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts &&
      ! grep -q "Promise.race" add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts
    </automated>
  </verify>
  <done>RED→GREEN pair; Pages uses env-var configuration path (NOT 3rd-arg) per codex MEDIUM-5; AbortController + clearTimeout pattern.</done>
  <acceptance_criteria>
    - 5/5 vitest tests pass on Pages healthz-snippet.test.ts
    - File contains `context.env.HEALTHZ_PROBE_TIMEOUT_MS` and the "narrowed for Pages per codex MEDIUM-5" comment
    - File does NOT add a third arg to onRequest
    - File contains `AbortController`, `clearTimeout`, no `Promise.race + reject`
    - gitnexus_impact recorded
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 1.6 (Wave 1, F2.supabase): healthz per-probe timeout — TS Supabase Edge (TDD) — R-rev-3 NARROWED</name>
  <files>add-observability/templates/ts-supabase-edge/healthz-snippet.ts, add-observability/templates/ts-supabase-edge/healthz-snippet.test.ts</files>
  <depends_on>none</depends_on>
  <read_first>
    - add-observability/templates/ts-supabase-edge/healthz-snippet.ts (the file being modified)
    - add-observability/templates/ts-supabase-edge/cron-monitor.test.ts:17 (existing Deno-friendly test seam — must not break per codex MEDIUM-4)
    - add-observability/templates/run-template-tests.sh:499 (pins @sentry/* to ^8.0.0)
    - add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts (reference)
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex MEDIUM-5
    - .planning/phases/23-observability-followups/CONTEXT.md D-03 (REVISED — per-stack heterogeneity)
  </read_first>
  <behavior>
    **Per codex MEDIUM-5: Planner-pick decision at execute time** between two paths (BOTH acceptable):
    - **(a) Module-level const:** `const PROBE_TIMEOUT_MS = 2000;` — operator edits template before deploying.
    - **(b) Env-var match Pages pattern:** `Number(Deno.env.get("HEALTHZ_PROBE_TIMEOUT_MS")) || DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS`.

    **Recommendation: pick (b)** for parity with Pages — keeps caller-configurability via env var. Use `Deno.env.get` (Supabase is Deno runtime).

    Test cases (mirror Task 1.4):
    - **Test 1**: fast probe ok
    - **Test 2**: hang → timeout sentinel
    - **Test 3**: env-var override (`Deno.env.set("HEALTHZ_PROBE_TIMEOUT_MS", "500")` in test setup)
    - **Test 4**: R06 fail-closed
    - **Test 5 (gemini MEDIUM-1)**: no unhandled rejection
  </behavior>
  <action>
    [BLOCKING] gitnexus_impact on supabase-edge healthzHandler.

    Mirror Task 1.4 structure. Add `DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000`, env-var override (`Deno.env.get("HEALTHZ_PROBE_TIMEOUT_MS")`), per-probe AbortController + setTimeout + try/finally + clearTimeout, `"timeout"` sentinel.

    Add inline comment:
    ```typescript
    // D-03 (narrowed for Supabase-Edge per codex MEDIUM-5): Deno runtime + restrictive
    // test seam → env-var configuration matches Pages pattern. Worker keeps 3rd-arg path.
    ```

    RED `test(23): F2 supabase-edge healthz per-probe timeout — RED`; GREEN `feat(23): F2 supabase-edge healthz per-probe timeout — Deno.env-driven (R-rev-3 narrowed) — GREEN`.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-supabase-edge && (npx vitest run healthz-snippet.test.ts 2>/dev/null || deno test --allow-env healthz-snippet.test.ts) &&
      grep -q "DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000" add-observability/templates/ts-supabase-edge/healthz-snippet.ts &&
      grep -q "HEALTHZ_PROBE_TIMEOUT_MS" add-observability/templates/ts-supabase-edge/healthz-snippet.ts &&
      grep -q "narrowed for Supabase-Edge per codex MEDIUM-5" add-observability/templates/ts-supabase-edge/healthz-snippet.ts &&
      grep -q "new AbortController" add-observability/templates/ts-supabase-edge/healthz-snippet.ts &&
      grep -q "clearTimeout" add-observability/templates/ts-supabase-edge/healthz-snippet.ts &&
      ! grep -q "Promise.race" add-observability/templates/ts-supabase-edge/healthz-snippet.ts
    </automated>
  </verify>
  <done>RED→GREEN pair for supabase-edge; env-var configuration; AbortController + clearTimeout; no Promise.race.</done>
  <acceptance_criteria>
    - 5/5 tests pass
    - Env-var override path present
    - "narrowed for Supabase-Edge per codex MEDIUM-5" comment present
    - AbortController + clearTimeout, no Promise.race
    - gitnexus_impact recorded
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 1.7 (Wave 1 CLOSER, F2.go): healthz per-probe timeout — Go fly-http (TDD) — R-rev-3 NARROWED + R-rev-8 wave-closer gitnexus_detect_changes</name>
  <files>add-observability/templates/go-fly-http/healthz_snippet.go, add-observability/templates/go-fly-http/healthz_snippet_test.go</files>
  <depends_on>none (closes Wave 1)</depends_on>
  <read_first>
    - add-observability/templates/go-fly-http/healthz_snippet.go (full file — HealthzHandler; line 62 is the upstream-probe Get(url) interface that codex MEDIUM-5 flagged)
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex MEDIUM-5 (Go's `Get(url)` can only race, not cancel — pick honest documentation alternative)
    - .planning/phases/23-observability-followups/CONTEXT.md D-03 (REVISED — per-stack heterogeneity)
  </read_first>
  <behavior>
    **Per codex MEDIUM-5: Pick honest-documentation alternative (NOT scope expansion).** Go's `Get(url)` interface can only race, not cancel. The `context.WithTimeout` will cap handler latency (the handler returns within timeout) but the underlying outbound HTTP call may continue in the background until it completes naturally. This is documented explicitly in code comment + CHANGELOG.

    Test cases:
    - **Test 1**: fast probe → 200 + `{"status":"ok","checks":{"db":true}}`
    - **Test 2**: hanging DB probe → 503 + `{"status":"degraded","checks":{"db":"timeout"}}` within 2.2s
    - **Test 3**: custom timeout via `HealthzDeps.ProbeTimeout` field
    - **Test 4**: R06 zero-probes path preserved
    - **Test 5 (NEW per codex MEDIUM-5 honest-doc alt)**: upstream `Get(url)` probe that hangs → handler returns within timeout with `"timeout"` sentinel, BUT we explicitly do NOT assert the underlying request was cancelled (it cannot be). Test verifies the handler latency contract only.
  </behavior>
  <action>
    [BLOCKING] gitnexus_impact on Go HealthzHandler.

    **RED commit** (`test(23): F2 go healthz per-probe timeout — RED`):
    Implement 5 tests per behaviour block. Test 5 uses a fake upstream prober that records "called but not cancelled" — the assertion is on handler latency, not probe cancellation.

    **GREEN commit** (`feat(23): F2 go healthz per-probe timeout — handler-latency cap only (R-rev-3 honest-doc per codex MEDIUM-5) — GREEN`):
    1. Modify healthz_snippet.go:
       a. Add `"time"` import
       b. Add constant + honest documentation:
          ```go
          // DefaultHealthzProbeTimeout is the D-03 default per-probe timeout. Override
          // per HealthzDeps.ProbeTimeout (zero value = default).
          //
          // IMPORTANT (D-03 narrowed for Go per codex MEDIUM-5): for probes whose
          // interface accepts context.Context (e.g., db.PingContext), the timeout
          // cancels the underlying call. For probes that take only a URL (e.g., the
          // upstream `Get(url)` interface), the timeout caps HANDLER LATENCY ONLY —
          // the underlying outbound HTTP call may continue in the background until it
          // completes naturally. Widening the upstream interface to accept
          // context.Context is a scope-expansion alternative deferred to a future phase.
          const defaultHealthzProbeTimeout = 2 * time.Second
          ```
       c. Add `ProbeTimeout time.Duration` to `HealthzDeps`.
       d. `checks` map type → `map[string]any{}` to allow `true`, `false`, `"timeout"`.
       e. `probeTimeout := deps.ProbeTimeout; if probeTimeout == 0 { probeTimeout = defaultHealthzProbeTimeout }`
       f. **DB probe (interface accepts ctx — fully cancellable):**
          ```go
          if deps.DB != nil {
            ctx, cancel := context.WithTimeout(r.Context(), probeTimeout)
            err := deps.DB.PingContext(ctx)
            cancel()
            switch {
            case err == nil:
              checks["db"] = true
            case errors.Is(err, context.DeadlineExceeded):
              checks["db"] = "timeout"
            default:
              checks["db"] = false
            }
          }
          ```
       g. **Upstream Get(url) probe (cannot cancel — race only):**
          ```go
          if deps.Upstream != nil {
            // codex MEDIUM-5: upstream prober interface accepts only URL, not ctx.
            // We race the call against a timer; on timeout, the request continues in
            // the background but the handler returns immediately.
            done := make(chan error, 1)
            go func() { done <- deps.Upstream.Get(deps.UpstreamURL) }()
            select {
            case err := <-done:
              if err == nil { checks["upstream"] = true } else { checks["upstream"] = false }
            case <-time.After(probeTimeout):
              checks["upstream"] = "timeout"  // background goroutine may still complete
            }
          }
          ```
       h. `allOK` loop: `for _, v := range checks { if v != true { allOK = false; break } }`
    2. Run `go test -run "TestHealthz" -count=1 ./...`. Assert 5/5 pass.
    3. Commit.

    **WAVE 1 CLOSER (R-rev-8): Run `gitnexus_detect_changes()` after the GREEN commit.** Verify only the symbols listed in `<gitnexus_required_symbols>` for Wave 1 (1.1-1.7) appear in the change report. If unexpected symbols flagged: STOP and surface as CHECKPOINT before proceeding to Wave 2.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/go-fly-http && go test -run "TestHealthz" -count=1 ./... &&
      grep -q "defaultHealthzProbeTimeout = 2 \\* time.Second" add-observability/templates/go-fly-http/healthz_snippet.go &&
      grep -q "context.WithTimeout" add-observability/templates/go-fly-http/healthz_snippet.go &&
      grep -q "narrowed for Go per codex MEDIUM-5" add-observability/templates/go-fly-http/healthz_snippet.go &&
      grep -q "HANDLER LATENCY ONLY" add-observability/templates/go-fly-http/healthz_snippet.go &&
      grep -q '"timeout"' add-observability/templates/go-fly-http/healthz_snippet.go
    </automated>
  </verify>
  <done>RED→GREEN pair; DB probe uses context-cancellation; Upstream probe uses race-only with honest "caps handler latency, not underlying call" documentation. gitnexus_detect_changes run as Wave 1 closer.</done>
  <acceptance_criteria>
    - All 5 Go tests pass
    - `defaultHealthzProbeTimeout = 2 * time.Second` literal present
    - Honest-documentation comment block present (HANDLER LATENCY ONLY)
    - DB probe uses `context.WithTimeout` + cancel; Upstream probe uses `select { case ... <-time.After }` race
    - R06 fail-closed preserved
    - gitnexus_impact recorded for HealthzHandler
    - **WAVE 1 CLOSER (R-rev-8): `gitnexus_detect_changes()` run; output verified against `<gitnexus_required_symbols>` Wave 1 rows; no unexpected symbols flagged**
    - Commit: `feat(23): F2 go healthz + Wave 1 closer gitnexus_detect_changes — GREEN`
  </acceptance_criteria>
</task>


<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 2 — F5 GUARDED Shape A refactor, one task per TS stack             -->
<!-- depends_on: Task 0.2 (ADR-0029 locks the Guarded contract)              -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto" tdd="true">
  <name>Task 2.1 (Wave 2, F5.worker): withCronMonitor GUARDED Shape A — TS Cloudflare Worker (TDD) — R-rev-1</name>
  <files>add-observability/templates/ts-cloudflare-worker/cron-monitor.ts, add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts</files>
  <depends_on>Task 0.2 (ADR-0029 locks the Guarded Shape A contract)</depends_on>
  <read_first>
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts FULL FILE (lines 137-148 PRESERVED; 148-181 REPLACED with Guarded block)
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts FULL FILE
    - **.planning/phases/23-observability-followups/CONTEXT.md §D-08 (AMENDED — Guarded Shape A canonical code block)** — this is the binding source
    - docs/decisions/0029-cron-monitor-sdk-composition.md (just authored in Task 0.2 — architectural rationale)
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex HIGH-1 (the empirical evidence for Guarded)
    - .planning/phases/22-sentry-crons-healthz/PLAN.md §R02, §R04 (the NARROWED-regression contracts)
    - .planning/phases/22-sentry-crons-healthz/CONTEXT.md D6, D11, D12 (PRESERVED contracts)
    - add-observability/templates/ts-cloudflare-worker/middleware.ts (outer wrapper — verify it catches POST-callback SDK errors per T-23-02 narrowed)
  </read_first>
  <behavior>
    Behavioural-parity test cases for cron-monitor.test.ts (EXTEND existing tests):

    - **Test F5.1 (RED first)**: happy path with explicit slug — assert `Sentry.withMonitor` called ONCE with `("fxsa-ingest-15min", <callback function>, undefined)`. Assert `captureCheckIn` NOT called directly from the wrapper.
    - **Test F5.2 (RED first)**: with `schedule` + `maxRuntimeSeconds` config — assert `Sentry.withMonitor` called with `(slug, callback, {schedule: {...}, maxRuntime: 240})` (D12 preserved).
    - **Test F5.3 (RED first)**: handler throws DURING execution — assert thrown error propagates (handler-thrown errors propagate per Guarded contract).
    - **Test F5.4 (RED first)**: SENTRY_DSN unset — assert handler runs unchanged AND `Sentry.withMonitor` NOT called (fail-safe R02 preserved at line 138 guard).
    - **Test F5.5 (RED first — D6 slug resolution)**: assert slug computed by `resolveSlug` is the slug passed to `Sentry.withMonitor`.
    - **Test F5.6 (NEW — codex Suggestion 2 — pre-callback regression)**: mock `Sentry.withMonitor` to throw BEFORE invoking the callback (simulate transport failure on `in_progress` check-in). Assert: (a) `handler` IS called exactly once (Guarded fallback), (b) no error propagates from `withCronMonitor`, (c) no crash. Test name: `"Sentry check-in setup throws before callback start → handler still runs unmonitored, no crash"`. RED state: original Shape A fails this test because handler is never invoked. GREEN state: Guarded fallback runs handler unmonitored.
    - **Test F5.7 (NEW — codex Suggestion 2 — post-callback propagation)**: mock `Sentry.withMonitor` to throw AFTER the callback completed successfully (simulate transport failure on `ok` check-in). Assert: (a) `handler` was called, (b) the post-callback error propagates from `withCronMonitor`. Test name: `"Sentry post-callback check-in throws → handler ran, error propagates to outer wrapper"`.

    - **Modify** existing tests asserting `captureCheckIn` directly: replace with F5.1-F5.7 cases. Update test file top-comment (lines 1-17) to reference D-08 GUARDED variant + ADR-0029.
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "withCronMonitor", direction: "upstream"})`; record risk. Per ./CLAUDE.md this is BLOCKING for symbol body edits and risk level MUST be reported in commit body. If HIGH or CRITICAL: include "proceed-anyway" rationale citing D-08 (Guarded) user authorization.

    Grep `withCronMonitor` callers across repo + downstream (fxsa, callbot). Document found consumers in commit body.

    **Verify outer wrapper catches POST-callback SDK errors per T-23-02 narrowed:**
    Read `add-observability/templates/ts-cloudflare-worker/middleware.ts` — confirm `withObservabilityScheduled` catches and rethrows. Document verdict in commit body. (Note: Guarded Shape A means PRE-callback errors fall back to unmonitored handler; only POST-callback errors propagate. Outer wrapper still needs to catch those.)

    **RED commit** (`test(23): F5 worker GUARDED Shape A behavioural-parity + pre-callback regression — RED`):
    1. Update cron-monitor.test.ts to mock `Sentry.withMonitor`:
       ```typescript
       const withMonitorMock = vi.fn();
       const captureCheckIn = vi.fn();
       vi.mock("@sentry/cloudflare", () => ({
         captureCheckIn: (...args: unknown[]) => captureCheckIn(...args),
         withMonitor: (...args: unknown[]) => withMonitorMock(...args),
       }));
       ```
       Default mock: `withMonitorMock.mockImplementation(async (_slug, cb) => cb());`. Override per-test:
       - F5.6: `withMonitorMock.mockImplementation(async () => { throw new Error("transport down"); });` (throws BEFORE cb runs)
       - F5.7: `withMonitorMock.mockImplementation(async (_slug, cb) => { await cb(); throw new Error("post-callback transport down"); });` (throws AFTER cb completes)
    2. Replace old tests with F5.1-F5.7 per `<behavior>`. Update top-comment to reference D-08 GUARDED + ADR-0029.
    3. Run `npx vitest run cron-monitor.test.ts 2>&1 | tee /tmp/red-f5-worker.txt`
    4. Assert: F5.1, F5.2, F5.3, F5.6, F5.7 FAIL. F5.4 + F5.5 may pass.
    5. Commit test file ONLY.

    **GREEN commit** (`feat(23): F5 worker GUARDED Shape A — handlerStarted fallback (R-rev-1) — GREEN`):
    1. Modify `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts`:
       a. Change import: `import { captureCheckIn } from "@sentry/cloudflare";` → `import * as Sentry from "@sentry/cloudflare";`
       b. PRESERVE lines 137-148 (outer body up to and including `const monitorConfig = buildMonitorConfig(config);`)
       c. REPLACE lines 148-181 with EXACTLY the Guarded Shape A block (canonical source: CONTEXT.md D-08):
          ```typescript
              // D-08 GUARDED Shape A (per ADR-0029, amended post-multi-AI-review).
              // PRESERVED: D6 slug resolution (above), R02 fail-safe (above), D12 monitorConfig forwarding (above),
              //   AND the "cron always runs" guarantee (Guarded fallback handles pre-callback SDK failures).
              // NARROWED REGRESSION (vs v0.6.0): only POST-callback SDK errors propagate to outer wrapper.
              //   PRE-callback errors (Sentry transport failing on in_progress check-in) trigger the
              //   fallback path below: handler runs unmonitored, no propagation, no skip.
              // ADDED: withIsolationScope wrapping per cron run. NOTE: handler-set scope state
              //   (Sentry.setTag, breadcrumbs inside cron body) may not be visible to outer
              //   error-capture handlers after isolation unwinds (per ADR-0029 honest semantic).
              let handlerStarted = false;
              try {
                await Sentry.withMonitor(
                  monitorSlug,
                  () => {
                    handlerStarted = true;
                    return handler(controller, env, ctx);
                  },
                  monitorConfig,
                );
              } catch (err) {
                if (!handlerStarted) {
                  // Sentry transport failed before handler ran — fall back to unmonitored.
                  await handler(controller, env, ctx);
                  return;
                }
                throw err; // handler-thrown OR post-callback errors propagate as before
              }
            };
          }
          ```
       d. DELETE `debugLog` + `isDebug` helpers (no longer used). Search for remaining `SENTRY_DEBUG` references; if found elsewhere, restore helpers; otherwise delete.
       e. Update JSDoc (lines 116-132):
          - Replace "SDK exceptions during checkin are caught and swallowed; opt-in `SENTRY_DEBUG=1` surfaces them" with: "POST-callback SDK exceptions propagate via `Sentry.withMonitor` to the outer `withObservabilityScheduled` capture path (D-08 narrowed regression vs v0.6.0). PRE-callback SDK failures trigger the Guarded fallback: handler runs unmonitored."
          - Add: "Each invocation runs inside its own `withIsolationScope` — note handler-set scope state may not be visible to outer error capture after isolation unwinds (D-08 documented addition)."
    2. Run `npx vitest run cron-monitor.test.ts`. Assert: F5.1-F5.7 + preserved D6 tests all pass.
    3. Run FULL worker harness: `npx vitest run`. Assert: zero regressions in Wave 1 healthz tests.
    4. Commit production file.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-cloudflare-worker && npx vitest run cron-monitor.test.ts &&
      grep -q "handlerStarted = false" add-observability/templates/ts-cloudflare-worker/cron-monitor.ts &&
      grep -q "GUARDED Shape A" add-observability/templates/ts-cloudflare-worker/cron-monitor.ts &&
      grep -q "fall back to unmonitored" add-observability/templates/ts-cloudflare-worker/cron-monitor.ts &&
      ! grep -q "debugLog\\|isDebug" add-observability/templates/ts-cloudflare-worker/cron-monitor.ts
    </automated>
  </verify>
  <done>RED→GREEN pair with Guarded Shape A; 7 tests pass including pre-callback regression (F5.6) and post-callback propagation (F5.7); handlerStarted flag wires the fallback.</done>
  <acceptance_criteria>
    - vitest reports all cron-monitor.test.ts (7 F5 + preserved tests) + healthz-snippet.test.ts (5) passing
    - cron-monitor.ts contains literal `handlerStarted = false`, `GUARDED Shape A`, `fall back to unmonitored`
    - cron-monitor.ts NO LONGER contains `debugLog` or `isDebug`
    - `resolveSlug` and `buildMonitorConfig` byte-identical to HEAD (D6 + D12 preservation)
    - middleware.ts verification verdict (does outer catch POST-callback SDK errors?) recorded in commit body
    - gitnexus_impact run; risk level + downstream caller list recorded in commit body
    - F5.6 (pre-callback regression) RED→GREEN transition explicit in commit log
    - F5.7 (post-callback propagation) RED→GREEN transition explicit in commit log
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 2.2 (Wave 2, F5.pages): withCronMonitor GUARDED Shape A — TS Cloudflare Pages (TDD) — R-rev-1</name>
  <files>add-observability/templates/ts-cloudflare-pages/cron-monitor.ts, add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts</files>
  <depends_on>Task 0.2 (ADR-0029)</depends_on>
  <read_first>
    - add-observability/templates/ts-cloudflare-pages/cron-monitor.ts FULL FILE
    - add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts FULL FILE
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts (just-edited GREEN reference)
    - .planning/phases/23-observability-followups/CONTEXT.md §D-08 (Guarded canonical block)
    - docs/decisions/0029-cron-monitor-sdk-composition.md
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex HIGH-1 (note: Pages has NO outer observability wrapper — pre-callback failure would go to external caller; Guarded mitigates this)
  </read_first>
  <behavior>
    Identical F5.1-F5.7 test shape as Task 2.1 (worker), adapted to pages-stack signature. Note: codex HIGH-1 highlighted that Pages has NO outer observability wrapper — so the pre-callback regression test F5.6 is ESPECIALLY critical for Pages (without Guarded, the cron skip would propagate directly to the external caller).
  </behavior>
  <action>
    [BLOCKING] gitnexus_impact on pages `withCronMonitor` symbol.

    Mirror Task 2.1. Same Guarded Shape A substitution: preserve outer body + slug + monitorConfig build; replace lifecycle with Guarded block (handlerStarted flag + pre-callback fallback). Same JSDoc updates + same helper removal.

    Add to commit body: "Pages has NO outer observability wrapper (codex HIGH-1) — the Guarded fallback is especially critical here; without it, pre-callback Sentry failures would skip the cron AND propagate to the external caller."

    Same RED + GREEN commit shape; commits use `pages` in scope label.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-cloudflare-pages && npx vitest run cron-monitor.test.ts &&
      grep -q "handlerStarted = false" add-observability/templates/ts-cloudflare-pages/cron-monitor.ts &&
      grep -q "GUARDED Shape A" add-observability/templates/ts-cloudflare-pages/cron-monitor.ts &&
      grep -q "fall back to unmonitored" add-observability/templates/ts-cloudflare-pages/cron-monitor.ts
    </automated>
  </verify>
  <done>RED→GREEN pair for pages stack; Guarded Shape A matches worker.</done>
  <acceptance_criteria>
    - All cron-monitor.test.ts tests (7 F5 + preserved) pass
    - Same literal-string criteria as Task 2.1 hold for pages file
    - Commit body documents the Pages-specific severity (no outer wrapper) of the Guarded mitigation
    - gitnexus_impact recorded
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 2.3 (Wave 2 CLOSER, F5.supabase): withCronMonitor GUARDED Shape A — TS Supabase Edge (TDD) — R-rev-1 + R-rev-6 (Deno seam) + R-rev-8 (gitnexus_detect_changes)</name>
  <files>add-observability/templates/ts-supabase-edge/cron-monitor.ts, add-observability/templates/ts-supabase-edge/cron-monitor.test.ts</files>
  <depends_on>Task 0.2 (ADR-0029)</depends_on>
  <read_first>
    - add-observability/templates/ts-supabase-edge/cron-monitor.ts FULL FILE (line 166 is the outer wrapper)
    - add-observability/templates/ts-supabase-edge/cron-monitor.test.ts:17 (existing Deno-friendly test seam — must not break per codex MEDIUM-4)
    - add-observability/templates/run-template-tests.sh:499 (pins @sentry/* to ^8.0.0 — verify version compat for Guarded shape)
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts (worker GREEN reference)
    - **.planning/phases/23-observability-followups/CONTEXT.md §D-08 (Guarded canonical block)**
    - docs/decisions/0029-cron-monitor-sdk-composition.md
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex MEDIUM-4 (Deno seam blocker — must verify @sentry/deno exports withMonitor BEFORE editing impl)
  </read_first>
  <behavior>
    **Per codex MEDIUM-4: TWO PRECONDITIONS before any implementation edit:**

    **Precondition 1: Verify `@sentry/deno` exports `withMonitor`.** Run a module-shape check:
    ```bash
    # Use the pinned @sentry/deno major from run-template-tests.sh:499
    cd add-observability/templates/ts-supabase-edge && \
      deno eval --no-prompt 'import("@sentry/deno").then(m => console.log("withMonitor type:", typeof m.withMonitor))'
    ```
    Expected: `withMonitor type: function`. If NOT function: **STOP. Escalate as CHECKPOINT.** Do NOT silently shim with a re-implementation from `@sentry/core`.

    **Precondition 2: Introduce `_setWithMonitorForTest` Deno-friendly seam BEFORE Guarded Shape A substitution.** The existing Supabase test suite (`cron-monitor.test.ts:17`) deliberately avoids module-boundary mocking under `deno test`. Adding a test-only export that the test file uses to inject a fake `withMonitor` keeps the seam pattern intact.

    Test cases (identical F5.1-F5.7 from Task 2.1, adapted for Deno seam):
    - Tests use `_setWithMonitorForTest(fakeWithMonitor)` in beforeEach; restore in afterEach.
    - F5.6 (pre-callback regression) and F5.7 (post-callback propagation) MUST pass via the seam.
  </behavior>
  <action>
    [BLOCKING] gitnexus_impact on supabase-edge `withCronMonitor`.

    **Step 0 (PRECONDITION — execute before any other step):**
    1. Verify `@sentry/deno` exports `withMonitor` via the deno eval command above. Document the verdict in commit body.
    2. If absent: STOP, escalate as CHECKPOINT to orchestrator with the verdict. Do NOT proceed.

    **Step 1 (PRECONDITION — introduce Deno-friendly seam BEFORE Shape A substitution):**
    Add to `cron-monitor.ts` BEFORE the Guarded block edit:
    ```typescript
    // Deno-friendly test seam (codex MEDIUM-4): the existing Supabase suite avoids
    // module-boundary mocking under `deno test`. This seam lets tests inject a fake
    // withMonitor without breaking that pattern. Production code uses Sentry.withMonitor
    // directly via the default reference below.
    let _withMonitorImpl: typeof Sentry.withMonitor = Sentry.withMonitor;
    export function _setWithMonitorForTest(impl: typeof Sentry.withMonitor) {
      _withMonitorImpl = impl;
    }
    ```
    Commit this scaffolding as `feat(23): F5 supabase-edge — _setWithMonitorForTest seam (precondition for Guarded Shape A per codex MEDIUM-4)`. (Standalone commit so the seam can be verified before the Shape A substitution lands.)

    **RED commit** (`test(23): F5 supabase-edge GUARDED Shape A behavioural-parity + pre-callback regression — RED`):
    1. Update cron-monitor.test.ts to use the seam:
       ```typescript
       import { _setWithMonitorForTest, withCronMonitor } from "./cron-monitor";

       const withMonitorMock = (vi || /* deno mock */ ...).fn();
       beforeEach(() => _setWithMonitorForTest(withMonitorMock));
       afterEach(() => _setWithMonitorForTest(Sentry.withMonitor));
       ```
       Implement F5.1-F5.7 per behaviour block. F5.6 + F5.7 use mock overrides per Task 2.1.
    2. Run the existing test command (vitest or deno test per existing seam).
    3. Assert F5.1, F5.2, F5.3, F5.6, F5.7 FAIL.
    4. Commit test file ONLY.

    **GREEN commit** (`feat(23): F5 supabase-edge GUARDED Shape A via _setWithMonitorForTest seam (R-rev-1 + R-rev-6) — GREEN`):
    1. Modify cron-monitor.ts:
       a. Replace the lifecycle block with the Guarded Shape A canonical block, BUT call `_withMonitorImpl` (the seamed reference) instead of `Sentry.withMonitor` directly:
          ```typescript
          let handlerStarted = false;
          try {
            await _withMonitorImpl(
              monitorSlug,
              () => {
                handlerStarted = true;
                return handler(controller, env, ctx);
              },
              monitorConfig,
            );
          } catch (err) {
            if (!handlerStarted) {
              await handler(controller, env, ctx);
              return;
            }
            throw err;
          }
          ```
       b. Same comment block as Task 2.1 (GUARDED Shape A, narrowed regression, isolation-scope honest note).
    2. Run tests via the existing seam. Assert F5.1-F5.7 pass.
    3. Commit.

    **WAVE 2 CLOSER (R-rev-8): Run `gitnexus_detect_changes()` after the GREEN commit.** Verify only Wave 2 expected symbols. If unexpected: STOP, surface as CHECKPOINT.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-supabase-edge && (npx vitest run cron-monitor.test.ts 2>/dev/null || deno test cron-monitor.test.ts) &&
      grep -q "handlerStarted = false" add-observability/templates/ts-supabase-edge/cron-monitor.ts &&
      grep -q "_setWithMonitorForTest" add-observability/templates/ts-supabase-edge/cron-monitor.ts &&
      grep -q "GUARDED Shape A" add-observability/templates/ts-supabase-edge/cron-monitor.ts &&
      grep -q "Deno-friendly test seam" add-observability/templates/ts-supabase-edge/cron-monitor.ts
    </automated>
  </verify>
  <done>RED→GREEN pair for supabase-edge with Deno-friendly seam preserved; Guarded Shape A via _setWithMonitorForTest; pre-callback regression test passes. Wave 2 gitnexus_detect_changes run.</done>
  <acceptance_criteria>
    - `@sentry/deno` `withMonitor` export verified in commit body (precondition 1)
    - `_setWithMonitorForTest` seam present and used by tests (precondition 2)
    - All F5.1-F5.7 tests pass
    - Literal-string criteria from Task 2.1 hold (handlerStarted, GUARDED Shape A, fall back to unmonitored)
    - If `@sentry/deno` export absent: executor escalated as CHECKPOINT (did NOT silently shim from @sentry/core)
    - **WAVE 2 CLOSER (R-rev-8): `gitnexus_detect_changes()` run; output verified; no unexpected symbols**
    - gitnexus_impact recorded
  </acceptance_criteria>
</task>


<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 3 — F3 SIGTERM split-trap design (codex HIGH-2)                   -->
<!-- depends_on: Task 0.1 (dispatcher extension precondition)                -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto" tdd="true">
  <name>Task 3.1 (Wave 3 CLOSER, F3): SIGTERM SPLIT trap (EXIT silent / INT exit 130 / TERM exit 143) + path-validated --pause-between-passes flag + test — R-rev-2 + R-rev-8</name>
  <files>migrations/run-tests.sh, templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh</files>
  <depends_on>Task 0.1 (dispatcher extension — without this, the new test name is a no-op)</depends_on>
  <read_first>
    - migrations/run-tests.sh FULL FILE
    - migrations/0019-sentry-crons-and-healthz.md (canonical 2-pass migration shape)
    - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh (the actual 2-pass implementation)
    - .planning/phases/23-observability-followups/CONTEXT.md D-05
    - .planning/phases/22-sentry-crons-healthz/SECURITY.md §S6
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex HIGH-2 (split trap design + path validation fix)
    - Threat-model T-23-05 (cleanup must not leak secrets, silent-on-success) and T-23-07 (path validation REWORKED — `${TMPDIR:-/tmp}` + explicit allow-list prefix)
  </read_first>
  <behavior>
    **Per codex HIGH-2: split trap design with three SEPARATE handlers (NOT a single `trap 'cleanup' INT TERM EXIT`).**

    - **`trap on_exit EXIT`**: runs silently on every exit (success OR signal). Idempotent. **NO warning output. NO signal re-raise.** Just cleans up state (e.g., removes pause signal file if it exists).
    - **`trap on_int INT`**: runs cleanup THEN `exit 130` (signal-compatible exit code: 128 + 2 = SIGINT).
    - **`trap on_term TERM`**: runs cleanup THEN `exit 143` (signal-compatible exit code: 128 + 15 = SIGTERM).

    **Path validation rework (T-23-07):**
    - Use `${TMPDIR:-/tmp}` (handle unset TMPDIR — previous `"$TMPDIR"/*` was bypassable when TMPDIR empty).
    - Explicit allow-list prefix patterns:
      - `${TMPDIR:-/tmp}/sigterm-test-*` — for fixture-driven tests
      - `migrations/test-fixtures/0019/*/sigterm-*` — for fixture-prefix fallback
    - Reject ANY path that doesn't match either pattern.

    Test cases (single new test, name: `test-sigterm-mid-apply-preserves-state`):

    1. **Signal-driven cleanup output check (positive)**: spawn engine with `--pause-between-passes "${TMPDIR:-/tmp}/sigterm-test-XXXX"` in background; wait for signal file; SIGTERM; assert engine exit code is **143** (not 0 or 1); assert NO `cron-monitor.ts` exists in any wrapper root; assert re-run produces canonical post-state with exit 0.
    2. **Silent-on-success (negative — codex HIGH-2 KEY ASSERTION)**: run the engine to NORMAL successful completion (no signal). Capture stderr. Assert `grep -q "cleanup" /tmp/normal-stderr.txt` returns NON-zero (cleanup output ABSENT for successful exits — EXIT trap must be silent).
    3. **T-23-05 (no secret leak)**: SIGTERM-driven cleanup output captured; assert `! grep -qE "(SENTRY_DSN|API_KEY|TOKEN)=" /tmp/cleanup-output.txt`
    4. **T-23-07 (path validation REWORKED)**:
       - `migrate-0019-…sh --pause-between-passes /etc/passwd` exits 2 with "test-only flag with non-allow-listed path" (rejected)
       - `migrate-0019-…sh --pause-between-passes "${TMPDIR:-/tmp}/sigterm-test-abc"` proceeds (allow-listed prefix)
       - `migrate-0019-…sh --pause-between-passes "migrations/test-fixtures/0019/06-test/sigterm-foo"` proceeds (allow-listed fixture prefix)
       - With `unset TMPDIR`: `migrate-0019-…sh --pause-between-passes /etc/passwd` STILL exits 2 (the `${TMPDIR:-/tmp}` default makes the validation robust)
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "emit_refuse_artifacts", direction: "upstream"})` AND `gitnexus_impact` on `run_all` in run-tests.sh; record risks.

    **RED commit** (`test(23): F3 SIGTERM split trap + path validation rework — RED`):
    1. Add test function `test_sigterm_mid_apply_preserves_state` to `migrations/run-tests.sh` (dispatcher entry exists from Task 0.1):
       ```bash
       test_sigterm_mid_apply_preserves_state() {
         local tmpdir; tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/sigterm-test-XXXX")
         local SIG="$tmpdir/sigterm-test-signal"
         # ... fixture setup mirroring 0019/01-fresh-apply ...

         # Case 1: signal-driven cleanup
         bash templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh \
           --templates-dir "$TEMPLATES" --project-dir "$tmpdir" \
           --pause-between-passes "$SIG" 2>"$tmpdir/sigterm-stderr.txt" &
         ENGINE_PID=$!
         for i in $(seq 1 50); do [ -f "$SIG" ] && break; sleep 0.2; done
         [ -f "$SIG" ] || { echo "engine never reached pause"; kill -9 $ENGINE_PID; FAIL=$((FAIL+1)); return; }
         kill -TERM $ENGINE_PID
         wait $ENGINE_PID; engine_exit=$?
         # ASSERT: exit code 143 (codex HIGH-2)
         [ "$engine_exit" -eq 143 ] || { echo "expected exit 143, got $engine_exit"; FAIL=$((FAIL+1)); return; }
         # ASSERT: no half-written canonical files
         find "$tmpdir" -name "cron-monitor.ts" -type f | grep -q . && { echo "half-written cron-monitor.ts"; FAIL=$((FAIL+1)); return; }
         # T-23-05: no secrets in cleanup
         grep -qE "(SENTRY_DSN|API_KEY|TOKEN)=" "$tmpdir/sigterm-stderr.txt" && { echo "secrets leaked"; FAIL=$((FAIL+1)); return; }

         # Case 2: silent-on-success (codex HIGH-2 KEY)
         local clean_tmpdir; clean_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/sigterm-test-clean-XXXX")
         # ... fixture setup (clean roots only — engine will exit 0) ...
         bash templates/.claude/scripts/migrate-0019-…sh --templates-dir "$TEMPLATES" --project-dir "$clean_tmpdir" \
           2>"$clean_tmpdir/normal-stderr.txt"
         normal_exit=$?
         [ "$normal_exit" -eq 0 ] || { echo "normal run expected exit 0, got $normal_exit"; FAIL=$((FAIL+1)); return; }
         # ASSERT: cleanup output ABSENT for successful exit (EXIT trap is silent)
         grep -q "cleanup" "$clean_tmpdir/normal-stderr.txt" && { echo "EXIT trap leaked cleanup output on success"; FAIL=$((FAIL+1)); return; }

         # Case 3: re-run succeeds
         bash templates/.claude/scripts/migrate-0019-…sh --templates-dir "$TEMPLATES" --project-dir "$tmpdir"
         [ $? -eq 0 ] || { echo "re-run failed"; FAIL=$((FAIL+1)); return; }

         # Case 4 (T-23-07 path validation):
         bash templates/.claude/scripts/migrate-0019-…sh --pause-between-passes /etc/passwd 2>"$tmpdir/badpath-stderr.txt"
         [ $? -eq 2 ] && grep -q "test-only flag with non-allow-listed path" "$tmpdir/badpath-stderr.txt" || { echo "bad-path rejection failed"; FAIL=$((FAIL+1)); return; }
         # Case 4b: with TMPDIR unset
         ( unset TMPDIR; bash templates/.claude/scripts/migrate-0019-…sh --pause-between-passes /etc/passwd 2>/dev/null )
         [ $? -eq 2 ] || { echo "bad-path rejection failed with TMPDIR unset"; FAIL=$((FAIL+1)); return; }
         # Case 4c: good fixture path
         bash templates/.claude/scripts/migrate-0019-…sh --pause-between-passes "migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/sigterm-foo" 2>/dev/null || true
         # (exits non-2 on the rest of arg parsing; just verify flag accepted)

         PASS=$((PASS+1))
         echo "${GREEN}PASS${RESET}: test-sigterm-mid-apply-preserves-state"
       }
       ```
    2. Run `bash migrations/run-tests.sh test-sigterm-mid-apply-preserves-state 2>&1 | tee /tmp/red-f3.txt`
    3. Assert test fails (engine has no split trap or path-validated flag yet).
    4. Commit test ONLY.

    **GREEN commit** (`feat(23): F3 split trap + path-validated --pause-between-passes (R-rev-2) — GREEN`):
    1. Modify `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`:
       a. Add flag parsing with REWORKED path validation:
          ```bash
          PAUSE_SIGFILE=""
          # in the while loop:
          --pause-between-passes)
            PAUSE_SIGFILE="$2"
            # T-23-07 REWORKED (codex HIGH-2): ${TMPDIR:-/tmp} default + explicit allow-list prefix.
            _tmp="${TMPDIR:-/tmp}"
            case "$PAUSE_SIGFILE" in
              "$_tmp"/sigterm-test-*) : ;;
              */migrations/test-fixtures/0019/*/sigterm-*) : ;;
              *)
                echo "migrate-0019: --pause-between-passes is a test-only flag with non-allow-listed path: $PAUSE_SIGFILE" >&2
                echo "migrate-0019: allowed prefixes are \${TMPDIR:-/tmp}/sigterm-test-* or migrations/test-fixtures/0019/*/sigterm-*" >&2
                exit 2
                ;;
            esac
            echo "migrate-0019: WARNING — --pause-between-passes is a test-only flag; do not use in production" >&2
            shift 2
            ;;
          ```
       b. **SPLIT TRAP DESIGN** (replace any prior `trap 'cleanup' INT TERM EXIT` formulation):
          ```bash
          # T-23-05 + codex HIGH-2: SPLIT trap.
          # EXIT runs silently on EVERY exit (success + signal). Idempotent. NO warning.
          # INT runs cleanup THEN exit 130 (signal-compatible).
          # TERM runs cleanup THEN exit 143 (signal-compatible).
          _cleanup_fired=0
          _do_cleanup() {
            [ "$_cleanup_fired" -eq 1 ] && return 0
            _cleanup_fired=1
            # Idempotent state teardown. NO env-var echo, NO partial-file dump (T-23-05).
            [ -n "$PAUSE_SIGFILE" ] && [ -f "$PAUSE_SIGFILE" ] && rm -f "$PAUSE_SIGFILE" 2>/dev/null
          }
          on_exit() { _do_cleanup; }  # silent
          on_int() { _do_cleanup; exit 130; }
          on_term() { _do_cleanup; exit 143; }
          trap on_exit EXIT
          trap on_int INT
          trap on_term TERM
          ```
       c. At the boundary between pass 1 and pass 2, insert the signal-file rendezvous:
          ```bash
          if [ -n "$PAUSE_SIGFILE" ]; then
            : > "$PAUSE_SIGFILE"
            for i in $(seq 1 300); do
              [ ! -f "$PAUSE_SIGFILE" ] && break
              sleep 0.1
            done
          fi
          ```
    2. ALSO add a SPLIT trap to `migrations/run-tests.sh` (harness-level — same shape, simpler cleanup body):
       ```bash
       _runtests_cleanup_fired=0
       _runtests_do_cleanup() {
         [ "$_runtests_cleanup_fired" -eq 1 ] && return 0
         _runtests_cleanup_fired=1
         # harness-level cleanup (intentionally empty — no shared state to tear down)
         :
       }
       trap '_runtests_do_cleanup' EXIT
       trap '_runtests_do_cleanup; exit 130' INT
       trap '_runtests_do_cleanup; exit 143' TERM
       ```
    3. Run `bash migrations/run-tests.sh test-sigterm-mid-apply-preserves-state`. Assert pass (all 4+ test cases).
    4. Run full harness `bash migrations/run-tests.sh`. Assert no regressions.
    5. Commit.

    **WAVE 3 CLOSER (R-rev-8): Run `gitnexus_detect_changes()`.** Verify Wave 3 expected symbols only.
  </action>
  <verify>
    <automated>
      bash migrations/run-tests.sh test-sigterm-mid-apply-preserves-state &&
      grep -q "trap on_exit EXIT" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "trap on_int INT" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "trap on_term TERM" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "exit 130" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "exit 143" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "non-allow-listed path" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q '\${TMPDIR:-/tmp}/sigterm-test-' templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q 'trap.*EXIT' migrations/run-tests.sh &&
      grep -q 'exit 130' migrations/run-tests.sh &&
      grep -q 'exit 143' migrations/run-tests.sh
    </automated>
  </verify>
  <done>RED→GREEN. 0019 engine has SPLIT trap (EXIT silent / INT exit 130 / TERM exit 143) + path-validated --pause-between-passes flag with `${TMPDIR:-/tmp}` fallback and allow-list prefix matching. run-tests.sh has matching split trap. Test asserts: signal-driven exit 143; silent-on-success (cleanup output absent for exit-0 runs); no secret leak; path validation rejects /etc/passwd even with TMPDIR unset. Wave 3 gitnexus_detect_changes run.</done>
  <acceptance_criteria>
    - `bash migrations/run-tests.sh test-sigterm-mid-apply-preserves-state` exits 0
    - **Split trap explicit**: `trap on_exit EXIT`, `trap on_int INT`, `trap on_term TERM` (NOT a single combined trap)
    - **EXIT handler silent on success**: `grep -q "cleanup" <normal-exit-stderr>` returns non-zero (codex HIGH-2 key assertion)
    - **Signal exit codes correct**: SIGTERM → exit 143; SIGINT → exit 130
    - **Path validation REWORKED**: `${TMPDIR:-/tmp}` default + allow-list prefix; rejects `/etc/passwd` even with TMPDIR unset
    - cleanup stderr contains no SENTRY_DSN/API_KEY/TOKEN echoes (T-23-05)
    - Full `migrations/run-tests.sh` passes (no regressions)
    - **WAVE 3 CLOSER (R-rev-8): `gitnexus_detect_changes()` run; verified against expected Wave 3 symbols**
    - gitnexus_impact recorded for affected symbols
    - RED commit + GREEN commit pair in history
  </acceptance_criteria>
</task>


<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 4 — D-07 default-flip with HONEST REFRAME (codex MEDIUM-6)         -->
<!-- depends_on: Task 3.1 (both edit 0019 engine; sequencing avoids conflicts) -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto">
  <name>Task 4.1 (Wave 4, D-07 audit): Migration 0017 atomic-refuse audit (read-only) — R-rev-5 HONEST REFRAME</name>
  <files>(no files modified; produces an audit note in commit body)</files>
  <depends_on>Task 3.1 (avoid file conflicts on 0019 engine)</depends_on>
  <read_first>
    - templates/.claude/scripts/migrate-0017-axiom-destination.sh (lines 352-425 — emit_refuse_artifacts function); **line 368 in particular** — codex MEDIUM-6 verified that 0017 ALREADY writes dirty-root patches on refuse, contradicting the original PLAN's "zero-side-effect refuse" framing
    - .planning/phases/23-observability-followups/CONTEXT.md D-07
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex MEDIUM-6 (honest reframe required)
  </read_first>
  <action>
    **REVISED audit posture per codex MEDIUM-6 (R-rev-5):** The original PLAN framed D-07 as "0019 will match 0017's zero-side-effect refuse". Codex MEDIUM-6 verified that 0017 ALREADY writes dirty-root patches on default refuse (at line 368). The accurate framing is:

    **"Default refuse no longer writes to CLEAN roots; DIRTY roots still receive recovery artifacts (.observability-0019.patch + .gitignore entries) for splice recovery."**

    Audit exit-condition: 0017 conforms to this HONEST-REFRAMED target (clean roots NOT patched; dirty roots ARE patched). The original audit would have falsely escalated when finding the dirty-root patches in 0017.

    Concretely:
    1. Read migrate-0017's `emit_refuse_artifacts` function and its caller in the all-clean-gate block.
    2. Verify: on default refuse path (ALLOW_PARTIAL=0), patches are NOT emitted to CLEAN_DIRS — only to DIRTY_DIRS. **This is the audit pass criterion. Dirty-root patches are EXPECTED and acceptable.**
    3. Verify: on --allow-partial path (ALLOW_PARTIAL=1), patches are emitted to all roots OR clean roots are simply applied.
    4. If 0017 conforms to honest-reframed target: record verdict in commit body and proceed to Task 4.2 to bring 0019 into alignment.
    5. If 0017 ALSO writes patches to CLEAN roots on default refuse (would be a 0017 bug): expand Task 4.2 to fix 0017 too, BUT this is unexpected — codex MEDIUM-6 already verified line 368 shows the honest-reframed behaviour.

    Commit: `chore(23): D-07 audit — migration 0017 atomic-refuse semantics honestly verified (R-rev-5)`.
    Commit body: documents the verdict + cites line 368 + explicit acknowledgment that 0017 writes dirty-root patches (NOT "zero-side-effect" — operator-honest framing).

    NO file changes if 0017 conforms (empty commit with `--allow-empty` acceptable).
  </action>
  <verify>
    <automated>
      # Verify 0017's existing behaviour matches the honest-reframed target:
      # patches emitted to dirty roots (expected, not a bug), NOT to clean roots in default mode.
      grep -q "emit_refuse_artifacts" templates/.claude/scripts/migrate-0017-axiom-destination.sh
    </automated>
  </verify>
  <done>Audit verdict recorded in commit body using honest framing. 0017 conforms (expected case per codex MEDIUM-6); no production-file changes.</done>
  <acceptance_criteria>
    - Commit body contains "AUDIT VERDICT:" followed by honest-framed assessment
    - Commit body explicitly acknowledges 0017 writes dirty-root patches on refuse (NOT "zero-side-effect")
    - Commit body cites codex MEDIUM-6 + line 368 as evidence
    - If 0017 conforms (expected): Task 4.2 proceeds as scoped
    - If 0017 needs fix (unexpected — would contradict codex's read): escalate to orchestrator before proceeding
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 4.2 (Wave 4 CLOSER, D-07): Migration 0019 atomic-refuse default-flip + fixture 06 + fixture 07 — R-rev-5 HONEST REFRAME + R-rev-8</name>
  <files>
    templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh,
    migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh,
    migrations/test-fixtures/0019/07-allow-partial-emits-patches/setup.sh,
    migrations/test-fixtures/0019/07-allow-partial-emits-patches/verify.sh,
    migrations/test-fixtures/0019/07-allow-partial-emits-patches/expected-exit
  </files>
  <depends_on>Task 4.1 (audit must pass first); Task 3.1 (avoid 0019 engine conflicts)</depends_on>
  <read_first>
    - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh lines 540-590 (emit_refuse_artifacts + all-clean gate)
    - migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh
    - migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/setup.sh
    - templates/.claude/scripts/migrate-0017-axiom-destination.sh §all-clean-gate (reference shape — 0019 aligns)
    - .planning/phases/23-observability-followups/CONTEXT.md D-07
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex MEDIUM-6 (honest reframe — DO NOT use "zero-side-effect" or "truly atomic refusal" language)
    - Task 4.1's audit verdict
  </read_first>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "emit_refuse_artifacts", direction: "upstream"})`; record risk.

    Per D-07 + R-rev-5 honest reframe: change the migrate-0019 engine's default refuse behaviour. **HONEST framing throughout — DO NOT say "zero-side-effect" or "truly atomic refusal".** Use: "default refuse no longer writes to CLEAN roots; DIRTY roots still receive recovery artifacts (.observability-0019.patch + .gitignore entries) for splice recovery."

    The --allow-partial flag (existing) AND new `ALLOW_PARTIAL=true` env var both restore the emit-everywhere behaviour for clean roots. Precedence: flag wins over env, both must explicitly opt in.

    **Step 1 — Engine edit** (single commit `feat(23): D-07 0019 default refuse no longer touches CLEAN roots; DIRTY roots keep recovery artifacts; ALLOW_PARTIAL env opt-in (R-rev-5 honest reframe)`):

    Edit `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`:

    a. Add ALLOW_PARTIAL env-var reading:
       ```bash
       # D-07: ALLOW_PARTIAL env var opt-in (CLI --allow-partial still wins).
       _env_allow_partial=0
       case "${ALLOW_PARTIAL:-}" in
         1|true|yes) _env_allow_partial=1 ;;
       esac
       if [ "$ALLOW_PARTIAL" -eq 0 ] && [ "$_env_allow_partial" -eq 1 ]; then
         ALLOW_PARTIAL=1
         info "ALLOW_PARTIAL env var detected — treating as --allow-partial."
       fi
       ```

    b. Modify `emit_refuse_artifacts` to gate CLEAN-root patch emission:
       ```bash
       emit_refuse_artifacts() {
         local i
         warn "  hand-modified wrapper root(s) detected:"
         for i in "${!DIRTY_DIRS[@]}"; do
           local dir="${DIRTY_DIRS[$i]}" stack="${DIRTY_STACKS[$i]}"
           warn "    DIRTY: $dir  (stack: $stack)"
           emit_refuse_artifacts_for "$dir" "$stack" "DIRTY"
           # ... existing per-file diff output preserved ...
           warn "      wrote recovery artefact: $dir/.observability-0019.patch"
           warn "      recover: (a) revert the wrapper drift; (b) re-run migrate-0019;"
           warn "               (c) optionally splice .observability-0019.patch manually."
         done

         # D-07 (R-rev-5 HONEST REFRAME): default refuse no longer writes to CLEAN roots.
         # DIRTY roots still receive .observability-0019.patch + .gitignore entries for splice recovery.
         # --allow-partial (or ALLOW_PARTIAL=1 env) restores v0.6.0 "patches everywhere on refuse" for operators
         # with existing manual-recovery automation.
         if [ "$ALLOW_PARTIAL" -eq 1 ]; then
           if [ ${#CLEAN_DIRS[@]} -gt 0 ]; then
             warn "  would-be-clean roots (patches emitted under --allow-partial for reference):"
             for i in "${!CLEAN_DIRS[@]}"; do
               warn "    CLEAN: ${CLEAN_DIRS[$i]}  (stack: ${CLEAN_STACKS[$i]})"
               emit_refuse_artifacts_for "${CLEAN_DIRS[$i]}" "${CLEAN_STACKS[$i]}" "CLEAN-skipped"
             done
           fi
         else
           if [ ${#CLEAN_DIRS[@]} -gt 0 ]; then
             info "  would-be-clean roots (patches NOT emitted by default; pass --allow-partial or set ALLOW_PARTIAL=1 to also emit patches for clean roots):"
             for i in "${!CLEAN_DIRS[@]}"; do
               info "    CLEAN: ${CLEAN_DIRS[$i]}  (stack: ${CLEAN_STACKS[$i]})"
             done
           fi
         fi
       }
       ```

    c. Update script `--help` output and top-of-file documentation to use HONEST reframe language. **Replace any mention of "zero-side-effect" or "truly atomic refusal" with "default refuse no longer touches clean roots; dirty roots still get recovery artifacts".**

    **Step 2 — Flip fixture 06's assertion:**

    Edit `migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh`:
    ```bash
    # D-07 (R-rev-5 honest reframe): DEFAULT refuse no longer writes to CLEAN roots.
    # DIRTY roots still receive .observability-0019.patch for splice recovery.
    test -f "$DIRTY/.observability-0019.patch" || { echo "patch not emitted for DIRTY root"; exit 1; }
    test -s "$DIRTY/.observability-0019.patch" || { echo "patch empty at DIRTY root"; exit 1; }
    for d in "$CLEAN_A" "$CLEAN_B"; do
      test ! -e "$d/.observability-0019.patch" || { echo "D-07 VIOLATION: patch emitted to clean root $d in DEFAULT refuse path"; exit 1; }
    done
    ```

    **Step 3 — Create fixture 07:**

    Create `migrations/test-fixtures/0019/07-allow-partial-emits-patches/`:
    - `expected-exit`: contents `0\n`
    - `setup.sh`: source fixture 06's setup (2 clean + 1 dirty)
    - `verify.sh`: assert
      - `bash migrate-0019-…sh --allow-partial …` exits 0 (clean roots applied, dirty skipped)
      - clean roots received cron-monitor.ts (migrated)
      - dirty root has NO cron-monitor.ts (skipped)
      - `.observability-0019.patch` present at DIRTY root AND CLEAN roots (--allow-partial restores emit-everywhere)

    Wire fixture 07 into harness: edit `migrations/run-tests.sh` `test_migration_0019` to include fixture 07 in its per-fixture loop.

    **Step 4** — Run full harness `bash migrations/run-tests.sh`. Assert all tests including fixture 06 (flipped), fixture 07 (new), and Task 3.1 sigterm test pass.

    **WAVE 4 CLOSER (R-rev-8): Run `gitnexus_detect_changes()`.** Verify Wave 4 expected symbols.

    Commit as a single semantic commit (engine + fixtures + harness wiring).
  </action>
  <verify>
    <automated>
      bash migrations/run-tests.sh test_migration_0019 &&
      grep -q "default refuse no longer writes to CLEAN roots" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "DIRTY roots still receive" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "ALLOW_PARTIAL env var detected" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      ! grep -q "zero-side-effect" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      ! grep -q "truly atomic refusal" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "D-07 VIOLATION" migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh &&
      test -f migrations/test-fixtures/0019/07-allow-partial-emits-patches/verify.sh &&
      test -f migrations/test-fixtures/0019/07-allow-partial-emits-patches/setup.sh &&
      test -f migrations/test-fixtures/0019/07-allow-partial-emits-patches/expected-exit
    </automated>
  </verify>
  <done>0019 engine default refuse no longer touches CLEAN roots; DIRTY roots still get recovery artifacts (honest framing). --allow-partial + ALLOW_PARTIAL=1 env both opt in to emit-everywhere; fixture 06 flipped; new fixture 07 covers --allow-partial. Wave 4 gitnexus_detect_changes run.</done>
  <acceptance_criteria>
    - Full 0019 fixture suite passes (fixtures 01-07)
    - Engine documentation uses honest reframe language; no "zero-side-effect" or "truly atomic refusal" strings present
    - Fixture 06 verify.sh asserts CLEAN roots have NO patch in default mode (D-07 VIOLATION sentinel)
    - Fixture 07 verify.sh asserts clean roots migrated AND patched under --allow-partial
    - ALLOW_PARTIAL=1 env var triggers opt-in (flag precedence preserved)
    - **WAVE 4 CLOSER (R-rev-8): `gitnexus_detect_changes()` run; verified**
    - gitnexus_impact on emit_refuse_artifacts recorded
  </acceptance_criteria>
</task>

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 5 — Version bump + CHANGELOG + final verification                   -->
<!-- (ADR-0029 moved to Wave 0 per codex Suggestion 7 / R-rev-7)             -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto">
  <name>Task 5.1 (Wave 5, D-01 part 1): SKILL.md version bump 0.6.0 → 0.7.0</name>
  <files>add-observability/SKILL.md</files>
  <depends_on>Tasks 2.1/2.2/2.3 (F5 lands first — version bump reflects the F5 behaviour change)</depends_on>
  <read_first>
    - add-observability/SKILL.md (line 3 currently `version: 0.6.0`)
    - .planning/phases/23-observability-followups/CONTEXT.md D-01
  </read_first>
  <action>
    Edit `add-observability/SKILL.md` line 3:
    - FROM: `version: 0.6.0`
    - TO: `version: 0.7.0`

    No other field changes. `implements_spec: 0.3.2` stays — Phase 23 doesn't change spec.
    No `claude-workflow` version bump (per D-01).
    No new migration (per N2).

    Commit: `chore(23): D-01 bump add-observability 0.6.0 → 0.7.0`. Commit body cites D-01 + Guarded Shape A withIsolationScope addition + narrowed post-callback regression as the honest minor-bump justification.
  </action>
  <verify>
    <automated>
      grep -q "^version: 0.7.0$" add-observability/SKILL.md &&
      grep -q "^implements_spec: 0.3.2$" add-observability/SKILL.md &&
      ! grep -q "^version: 0.6.0$" add-observability/SKILL.md
    </automated>
  </verify>
  <done>add-observability/SKILL.md is at version 0.7.0.</done>
  <acceptance_criteria>
    - Line 3 of add-observability/SKILL.md is exactly `version: 0.7.0`
    - No other lines in frontmatter changed
    - No claude-workflow SKILL.md version touched
    - No new migration file created
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 5.2 (Wave 5, D-01 part 2): CHANGELOG.md 0.7.0 entry — R-rev-1 narrowed regression + R-rev-5 honest D-07 reframe + R-rev-9 AbortController note</name>
  <files>add-observability/CHANGELOG.md</files>
  <depends_on>Task 5.1</depends_on>
  <read_first>
    - add-observability/CHANGELOG.md (if exists; if not, create)
    - add-observability/SKILL.md (post Task 5.1 — confirm 0.7.0)
    - .planning/phases/23-observability-followups/CONTEXT.md §"Resolved decisions" (D-08 amended Guarded; D-07 honest reframe)
    - docs/decisions/0029-cron-monitor-sdk-composition.md (Wave 0 — the architectural rationale)
    - .planning/phases/23-observability-followups/23-REVIEWS.md (revision provenance)
  </read_first>
  <action>
    Create or modify `add-observability/CHANGELOG.md` with a `## 0.7.0 — 2026-05-29` entry at top.

    If file doesn't exist, create with:
    ```markdown
    # add-observability — CHANGELOG

    All notable changes to the `add-observability` skill. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

    Versioning: this skill ships an independent SemVer track from `claude-workflow`. Minor bumps reflect observable downstream behaviour changes in scaffolded templates.

    ```

    The 0.7.0 entry MUST contain these sections with REVISED language:

    ```markdown
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
    - **Migration 0019 atomic-refuse semantics flipped (D-07 — honest reframe per codex MEDIUM-6).** The default refuse path NO LONGER WRITES TO CLEAN ROOTS. DIRTY roots still receive `.observability-0019.patch` + `.gitignore` entries for splice recovery (unchanged from v0.6.0 — this is NOT "zero-side-effect refuse"). Operators who want v0.6.0 "patches everywhere on refuse" for manual splice-aid pass `--allow-partial` (CLI) or `ALLOW_PARTIAL=1` (env). Flag wins over env; both must explicitly opt in.

    ### Regressed (documented — NARROWED vs original Shape A)

    - **R02/R04 SDK-error swallow drops only for POST-callback errors** in `withCronMonitor`. Pre-callback errors (Sentry transport failing on `in_progress`) trigger the Guarded fallback — handler runs unmonitored, no propagation. Post-callback errors (transport failing on `ok`/`error` after handler completed) propagate to the outer `withObservabilityScheduled` capture path. **Operator action**: if your outer wrapper catches SDK errors, no change needed. If you relied on silent swallow to keep cron handlers running through Sentry outages, the new behaviour: pre-callback failures fall back to unmonitored execution; post-callback failures surface via outer wrapper. `SENTRY_DEBUG=1` no longer surfaces SDK call failures from inside `withCronMonitor`.

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
    ```

    Commit: `docs(23): D-01 CHANGELOG 0.7.0 entry — Guarded Shape A narrowed regression + honest D-07 reframe + F2 per-stack`.
  </action>
  <verify>
    <automated>
      grep -q "^## 0.7.0" add-observability/CHANGELOG.md &&
      grep -q "Guarded Shape A" add-observability/CHANGELOG.md &&
      grep -q "narrowed" add-observability/CHANGELOG.md &&
      grep -q "POST-callback" add-observability/CHANGELOG.md &&
      grep -q "withIsolationScope" add-observability/CHANGELOG.md &&
      grep -q "HONEST SEMANTIC" add-observability/CHANGELOG.md &&
      grep -q "handler-set scope state" add-observability/CHANGELOG.md &&
      grep -q "AbortController" add-observability/CHANGELOG.md &&
      grep -q "ALLOW_PARTIAL\\|--allow-partial" add-observability/CHANGELOG.md &&
      grep -q "default refuse path NO LONGER WRITES TO CLEAN ROOTS" add-observability/CHANGELOG.md &&
      grep -q "DIRTY roots still receive" add-observability/CHANGELOG.md &&
      ! grep -q "zero-side-effect" add-observability/CHANGELOG.md &&
      grep -q "SPLIT trap" add-observability/CHANGELOG.md &&
      grep -q "exit 130" add-observability/CHANGELOG.md &&
      grep -q "exit 143" add-observability/CHANGELOG.md &&
      grep -q "F1\\|INIT.md" add-observability/CHANGELOG.md &&
      grep -q "D-09\\|sentry-go" add-observability/CHANGELOG.md
    </automated>
  </verify>
  <done>CHANGELOG.md has a 0.7.0 entry covering all 5 F-items + D-07 honest reframe + D-09 + narrowed Guarded regression + honest isolation-scope semantic + per-stack F2.</done>
  <acceptance_criteria>
    - 0.7.0 entry exists
    - Guarded Shape A + narrowed regression (post-callback only) explicit
    - Honest isolation-scope semantic (handler-set scope state may not propagate) explicit
    - D-07 honest reframe (no "zero-side-effect"; DIRTY roots still get artifacts) explicit
    - F2 per-stack heterogeneity documented (Worker 3rd-arg / Pages env / Supabase Deno.env / Go handler-latency-only)
    - AbortController + clearTimeout pattern called out (gemini MEDIUM-1)
    - F3 split trap (EXIT silent / INT 130 / TERM 143) called out
    - F1, F4, D-09 in Internal section
    - Operator migration notes section
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 5.3 (Wave 5 CLOSER, final verification): Full test harness pass + named-test presence check (G6 REPLACED) + global gitnexus_detect_changes — R-rev-4 + R-rev-8</name>
  <files>(no files modified; verification gate)</files>
  <depends_on>Tasks 5.1, 5.2 (all prior waves complete)</depends_on>
  <read_first>
    - migrations/run-tests.sh
    - add-observability/templates/run-template-tests.sh
    - .planning/phases/23-observability-followups/CONTEXT.md G6 (REPLACED gate shape — see action)
    - .planning/phases/23-observability-followups/23-REVIEWS.md §Codex MEDIUM-7 (G6 numeric counter is non-executable)
  </read_first>
  <action>
    Final pre-commit gate before /gsd-review. **G6 numeric counter is REPLACED (per codex MEDIUM-7) — harnesses have no test-total summary, so numeric gates are non-executable. New gate: named-test presence + harness exit 0.**

    1. Run migration harness end-to-end:
       ```bash
       bash migrations/run-tests.sh 2>&1 | tee /tmp/final-migration-tests.txt
       echo "exit=$?"
       ```
       Assertions (REPLACED — per R-rev-4):
       - Exit code 0
       - **Named-test presence**: `grep -q "PASS.*test-skill-md-version-matches-latest-migration-to-version" /tmp/final-migration-tests.txt`
       - **Named-test presence**: `grep -q "PASS.*test-sigterm-mid-apply-preserves-state" /tmp/final-migration-tests.txt`
       - **NO numeric counter check** (codex MEDIUM-7: harness has no global summary)

    2. Run template harness end-to-end:
       ```bash
       bash add-observability/templates/run-template-tests.sh all 2>&1 | tee /tmp/final-template-tests.txt
       echo "exit=$?"
       ```
       Assertions:
       - Exit code 0
       - **Named-test files present in invocation list**: `grep -q "healthz-snippet.test.ts" /tmp/final-template-tests.txt` (proves F2 test files invoked across stacks)
       - **Named-test files present**: `grep -q "cron-monitor.test.ts" /tmp/final-template-tests.txt` (proves F5 parity tests invoked)
       - **NO numeric counter check**

    3. **Global gitnexus_detect_changes()** (final gate per ./CLAUDE.md):
       - `gitnexus_detect_changes()` — verify changes only affect expected symbols per `<gitnexus_required_symbols>`
       - If unexpected symbols flagged: CHECKPOINT, do not commit
       - This is the FINAL global pass; wave-closer detect_changes already ran in 1.7 / 2.3 / 3.1 / 4.2

    4. Phase summary to stdout:
       ```
       Phase 23 — observability-followups — FINAL VERIFICATION
       =======================================================
       Migration harness exit:    0
       Migration named tests:     test-skill-md-version-matches-latest-migration-to-version PASS
                                  test-sigterm-mid-apply-preserves-state PASS
       Template harness exit:     0
       Template test invocations: healthz-snippet.test.ts (× 4 stacks), cron-monitor.test.ts (× 3 stacks)
       gitnexus changes:          expected (matches <gitnexus_required_symbols> table)
       Files modified:            <count> across <stacks-changed>
       Decisions covered:         D-01..D-09 (D-08 amended to Guarded)
       Revisions applied:         R-rev-1..R-rev-9 (all 9 from 23-REVIEWS.md)
       ADR-0029:                  authored in Wave 0
       SKILL.md:                  0.6.0 → 0.7.0
       CHANGELOG.md:              0.7.0 entry added (honest reframe + narrowed regression)
       ```

    Commit: `chore(23): final verification — all harnesses green + named tests present; Phase 23 ready for /gsd-review`. May be `--allow-empty`.
  </action>
  <verify>
    <automated>
      bash migrations/run-tests.sh 2>&1 | tee /tmp/final-migration-tests.txt &&
      grep -q "PASS.*test-skill-md-version-matches-latest-migration-to-version" /tmp/final-migration-tests.txt &&
      grep -q "PASS.*test-sigterm-mid-apply-preserves-state" /tmp/final-migration-tests.txt &&
      bash add-observability/templates/run-template-tests.sh all
    </automated>
  </verify>
  <done>Both harnesses pass with named-test presence (G6 REPLACED gate). gitnexus_detect_changes global gate clean. Phase summary printed.</done>
  <acceptance_criteria>
    - migrations/run-tests.sh exits 0
    - Two named tests appear in PASS output (presence check, NOT numeric counter)
    - add-observability/templates/run-template-tests.sh all exits 0
    - Template-side new test files appear in invocation list
    - gitnexus_detect_changes() reports only expected symbols
    - Phase summary printed
  </acceptance_criteria>
</task>

</tasks>


<verification>
**Phase-level verification (run after Task 5.3):**

1. **Decision coverage** — every D-XX (D-01..D-09) has at least one task implementing it:
   - D-01 → Tasks 5.1 + 5.2
   - D-02 → entire batched plan (this PLAN.md is one phase, not split)
   - D-03 → Tasks 1.4 + 1.5 + 1.6 + 1.7 (REVISED per-stack heterogeneity per codex MEDIUM-5)
   - D-04 → Task 1.3 (uses grep + awk only)
   - D-05 → Task 3.1 (`--pause-between-passes` flag with reworked path validation)
   - D-06 → Task 1.3 (test name + location); Task 0.1 dispatcher precondition
   - D-07 → Tasks 4.1 + 4.2 (HONEST REFRAME per codex MEDIUM-6)
   - **D-08 → Tasks 2.1 + 2.2 + 2.3 (GUARDED Shape A per CONTEXT.md amendment + R-rev-1) + Task 0.2 (ADR-0029 moved to Wave 0 per R-rev-7)**
   - D-09 → Task 1.2

2. **Revision coverage** — every R-rev-N from `23-REVIEWS.md` has a task implementing it:
   - R-rev-1 (Guarded Shape A) → Tasks 2.1, 2.2, 2.3 + Task 0.2 ADR
   - R-rev-2 (split trap) → Task 3.1
   - R-rev-3 (F2 per-stack) → Tasks 1.4, 1.5, 1.6, 1.7
   - R-rev-4 (G6 gate replacement) → Task 0.1 (dispatcher) + Task 5.3 (named-test check)
   - R-rev-5 (D-07 honest reframe) → Tasks 4.1, 4.2, 5.2 CHANGELOG
   - R-rev-6 (Supabase Deno seam) → Task 2.3
   - R-rev-7 (ADR-0029 to Wave 0) → Task 0.2 (was 5.1)
   - R-rev-8 (GitNexus per-wave) → Tasks 1.7, 2.3, 3.1, 4.2, 5.3 (wave closers)
   - R-rev-9 (gemini F2 unhandled rejection) → Tasks 1.4, 1.5, 1.6 (AbortController + clearTimeout)

3. **Goal coverage** — every G1..G8 has evidence:
   - G1 → INIT.md 4 stack subsections (Task 1.1)
   - G2 → 4 healthz-snippet timeout impls + tests (Tasks 1.4-1.7) with per-stack heterogeneity
   - G3 → split trap + sigterm test (Task 3.1)
   - G4 → drift test (Task 1.3) with Task 0.1 dispatcher precondition
   - G5 → SKILL.md 0.7.0; no claude-workflow bump; no new migration (Tasks 5.1 + 5.2 + N2)
   - **G6 → REPLACED per codex MEDIUM-7**: named-test presence + harness exit 0 (NOT numeric counter) — see Task 5.3
   - G7 → Guarded Shape A composition tests + impl (Tasks 2.1-2.3) including pre-callback regression test per stack
   - G8 → Go SDK gap doc note (Task 1.2)

4. **Threat-model coverage** — every T-23-NN has a mitigation owner task:
   - T-23-01 (I, withIsolationScope honest semantic) → Tasks 2.1-2.3 + ADR-0029
   - T-23-02 (D, NARROWED — Guarded preserves cron-always-runs) → Tasks 2.1-2.3 (pre-callback regression test F5.6 + middleware.ts verification)
   - T-23-03 (I, healthz timing oracle) → Tasks 1.4-1.7 (per-stack timeouts + "timeout" sentinel)
   - T-23-04 (D, leaked resources) → Tasks 1.4-1.7 (AbortController + clearTimeout in try/finally)
   - T-23-05 (T, signal cleanup secret leak + silent-on-success) → Task 3.1
   - T-23-06 (E, --allow-partial misuse) → Task 5.2 (CHANGELOG operator note) — ACCEPTED
   - T-23-07 (S, test-only flag path validation REWORKED) → Task 3.1 (`${TMPDIR:-/tmp}` + allow-list prefix)

5. **G6 gate (REPLACED per codex MEDIUM-7):**
   - migrations/run-tests.sh: assert harness exit 0 + grep `PASS.*test-skill-md-version-matches-latest-migration-to-version` + grep `PASS.*test-sigterm-mid-apply-preserves-state`
   - add-observability/templates/run-template-tests.sh all: assert harness exit 0 + presence of new test files in invocation
   - **No numeric counter check** — harnesses lack the necessary global summary mechanism

6. **gitnexus_impact + detect_changes ledger** — `<gitnexus_required_symbols>` table fully populated. Wave-closer detect_changes in 1.7 / 2.3 / 3.1 / 4.2 / 5.3 per codex Suggestion 8.
</verification>

<success_criteria>
- [ ] All 6 waves executed in order; tasks within waves 1, 2 (and Wave 0) may parallelise
- [ ] Wave 0: Task 0.1 (dispatcher extension) + Task 0.2 (ADR-0029) — 2 commits, parallel-safe
- [ ] Wave 1: F1 + D-09 + F4 + F2×4 stacks (7 tasks; mix of RED+GREEN pairs)
- [ ] Wave 2: F5×3 stacks GUARDED Shape A (6 commits minimum + 1 supabase seam precondition = ~7 commits)
- [ ] Wave 3: F3 split trap (2 commits: RED + GREEN)
- [ ] Wave 4: D-07 audit (1 commit) + D-07 implementation (1 commit)
- [ ] Wave 5: SKILL.md + CHANGELOG.md + final verification (3 commits, ADR moved to Wave 0)
- [ ] Total commit count: ~24-26 commits (was 22-24 pre-revision; +Wave 0 + supabase seam precondition)
- [ ] add-observability/SKILL.md = `version: 0.7.0`
- [ ] add-observability/CHANGELOG.md has `## 0.7.0` entry with honest D-07 reframe + narrowed Guarded regression + AbortController callout
- [ ] docs/decisions/0029-cron-monitor-sdk-composition.md exists (WAVE 0) with 5 rejected shapes (incl. original Shape A)
- [ ] No claude-workflow SKILL.md version touched
- [ ] No new migration file in migrations/
- [ ] migrations/run-tests.sh exits 0; two new named tests appear in PASS output
- [ ] add-observability/templates/run-template-tests.sh all exits 0
- [ ] gitnexus_detect_changes() (global + wave-closers) reports only expected symbols
- [ ] Threat-model dispositions documented in commits where mitigations land
- [ ] Branch `feat/observability-followups-v0.7.0` ready for re-review via `/gsd-review --phase 23 --all` to confirm HIGH concerns landed
</success_criteria>

<output>
After completion:
1. Create `.planning/phases/23-observability-followups/SUMMARY.md` from $HOME/.claude/get-shit-done/templates/summary.md
2. Cut PR `feat: observability follow-ups + GUARDED withCronMonitor Sentry.withMonitor composition (add-observability 0.7.0)` against `main` with PR body referencing CONTEXT.md (amended) + ADR-0029 (Wave 0) + CHANGELOG.md 0.7.0 + narrowed regression callout + 9 revision IDs from 23-REVIEWS.md
3. Re-run `/gsd-review --phase 23 --all` (codex + gemini) to confirm HIGH concerns landed and verdict moves to LOW
4. Mandatory `/cso` per global CLAUDE.md — F5 changes how Sentry credentials/check-in payloads flow through `withIsolationScope` boundaries
5. `/qa` SKIPPED — no dev server in this repo
</output>
