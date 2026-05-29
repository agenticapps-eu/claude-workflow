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
    - "All 4 /healthz snippets ship a per-probe timeout: TS uses AbortSignal.timeout(DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS) with default 2000; Go uses context.WithTimeout(ctx, defaultHealthzProbeTimeout) with default 2*time.Second"
    - "Aborted probes report as {status: degraded, checks: {<probeName>: 'timeout'}} (string sentinel distinguishes timeout from genuine false)"
    - "migrations/run-tests.sh and templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh trap INT TERM EXIT and run cleanup before re-raising (no top-level migrations/apply.sh exists in this repo — see Task 3.1 behaviour block)"
    - "Test test-sigterm-mid-apply-preserves-state uses the test-only --pause-between-passes <signal-file> engine flag; passes deterministically with no sleeps"
    - "Test test-skill-md-version-matches-latest-migration-to-version asserts skill/SKILL.md version equals the highest-numbered migration file's to_version using only grep + awk (no yq)"
    - "All 3 TS cron-monitor.ts files have lines 137-148 preserved verbatim (fail-safe + slug resolution + monitorConfig build) and lines 148-181 replaced by a single `await Sentry.withMonitor(monitorSlug, () => handler(controller, env, ctx), monitorConfig);` call inside the existing try/catch scaffold"
    - "Each of the 3 TS cron-monitor.test.ts files contains behavioural-parity tests asserting Sentry.withMonitor is called with (slug, callback, monitorConfig) and captureCheckIn is NOT called directly from the wrapper"
    - "Go templates/go-fly-http/cron_monitor.go gains a ≤5-line package-doc note explaining sentry-go ships no WithMonitor equivalent; symbol body unchanged"
    - "Migration 0019's emit_refuse_artifacts function no longer emits .observability-0019.patch to CLEAN_DIRS in the default refuse path; --allow-partial (or ALLOW_PARTIAL=true env) restores the emit-to-all-roots behaviour"
    - "Fixture 06 verify.sh asserts the new default: clean roots receive NO patches; only the dirty root receives a patch on default refuse"
    - "New fixture 07 exercises --allow-partial and asserts clean roots are migrated, dirty root is skipped + patched"
    - "add-observability/SKILL.md version field is 0.7.0"
    - "add-observability/CHANGELOG.md has a 0.7.0 entry calling out F2 healthz timeout, F5 withCronMonitor refactor with R02/R04 SDK-error-swallow regression + withIsolationScope addition, and D-07 migration engine default-flip with --allow-partial opt-in path"
    - "docs/decisions/0029-cron-monitor-sdk-composition.md exists with Context, Decision (Shape A), Alternatives Rejected (Shapes B/C/D/F with specific contract each regresses), and Consequences"
    - "Full migration test harness (migrations/run-tests.sh) passes after all changes; full template test harness (add-observability/templates/run-template-tests.sh all) passes after all changes"
  artifacts:
    - path: "add-observability/init/INIT.md"
      provides: "F1 per-stack Phase 5 composition notes"
      contains: "withCronMonitor"
    - path: "add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts"
      provides: "F2 TS worker per-probe timeout via AbortSignal.timeout"
      contains: "DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS"
    - path: "add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts"
      provides: "F2 TS pages per-probe timeout"
      contains: "DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS"
    - path: "add-observability/templates/ts-supabase-edge/healthz-snippet.ts"
      provides: "F2 TS supabase-edge per-probe timeout"
      contains: "DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS"
    - path: "add-observability/templates/go-fly-http/healthz_snippet.go"
      provides: "F2 Go per-probe timeout via context.WithTimeout"
      contains: "defaultHealthzProbeTimeout"
    - path: "add-observability/templates/ts-cloudflare-worker/cron-monitor.ts"
      provides: "F5 Shape A composition: Sentry.withMonitor underneath outer wrapper"
      contains: "Sentry.withMonitor"
    - path: "add-observability/templates/ts-cloudflare-pages/cron-monitor.ts"
      provides: "F5 Shape A composition (pages)"
      contains: "Sentry.withMonitor"
    - path: "add-observability/templates/ts-supabase-edge/cron-monitor.ts"
      provides: "F5 Shape A composition (supabase-edge)"
      contains: "Sentry.withMonitor"
    - path: "add-observability/templates/go-fly-http/cron_monitor.go"
      provides: "D-09 sentry-go SDK gap doc note"
      contains: "sentry-go"
    - path: "migrations/run-tests.sh"
      provides: "F3 sigterm test + F4 skill-md drift test + INT/TERM/EXIT trap"
      contains: "test-sigterm-mid-apply-preserves-state"
    - path: "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
      provides: "F3 SIGTERM trap in the 2-pass atomic migration engine (no top-level migrations/apply.sh exists — Task 3.1's resolution lands the trap here AND in migrations/run-tests.sh)"
      contains: "trap 'cleanup' INT TERM EXIT"
    - path: "migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh"
      provides: "D-07 fixture 06 flipped assertion"
      contains: "no patch"
    - path: "migrations/test-fixtures/0019/07-allow-partial-emits-patches/verify.sh"
      provides: "D-07 fixture 07 --allow-partial path"
      contains: "allow-partial"
    - path: "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
      provides: "D-07 default-flip in emit_refuse_artifacts"
      contains: "ALLOW_PARTIAL"
    - path: "add-observability/SKILL.md"
      provides: "D-01 version bump 0.6.0 → 0.7.0"
      contains: "version: 0.7.0"
    - path: "add-observability/CHANGELOG.md"
      provides: "D-01 0.7.0 release notes"
      contains: "0.7.0"
    - path: "docs/decisions/0029-cron-monitor-sdk-composition.md"
      provides: "ADR-0029 capturing D-08 Shape A rationale + rejected shapes"
      contains: "Shape A"
  key_links:
    - from: "add-observability/templates/ts-cloudflare-worker/cron-monitor.ts"
      to: "@sentry/cloudflare"
      via: "Sentry.withMonitor(monitorSlug, () => handler(...), monitorConfig)"
      pattern: "Sentry\\.withMonitor\\("
    - from: "add-observability/templates/ts-cloudflare-pages/cron-monitor.ts"
      to: "@sentry/cloudflare"
      via: "Sentry.withMonitor(monitorSlug, () => handler(...), monitorConfig)"
      pattern: "Sentry\\.withMonitor\\("
    - from: "add-observability/templates/ts-supabase-edge/cron-monitor.ts"
      to: "@sentry/cloudflare"
      via: "Sentry.withMonitor(monitorSlug, () => handler(...), monitorConfig)"
      pattern: "Sentry\\.withMonitor\\("
    - from: "add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts"
      to: "global AbortSignal"
      via: "AbortSignal.timeout(DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS) passed to probe call"
      pattern: "AbortSignal\\.timeout\\("
    - from: "add-observability/templates/go-fly-http/healthz_snippet.go"
      to: "stdlib context"
      via: "context.WithTimeout(r.Context(), defaultHealthzProbeTimeout)"
      pattern: "context\\.WithTimeout\\("
    - from: "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
      to: "cleanup function"
      via: "trap 'cleanup' INT TERM EXIT (also mirrored in migrations/run-tests.sh per Task 3.1)"
      pattern: "trap.*cleanup.*INT.*TERM.*EXIT"
    - from: "migrations/run-tests.sh"
      to: "skill/SKILL.md + migrations/<latest>.md"
      via: "test-skill-md-version-matches-latest-migration-to-version function"
      pattern: "test-skill-md-version-matches-latest-migration-to-version"
    - from: "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
      to: "operator opt-in flag"
      via: "ALLOW_PARTIAL gating around clean-root patch emission"
      pattern: "ALLOW_PARTIAL.*-eq 1"
---

<objective>
Ship `add-observability 0.7.0` minor — five batched follow-ups from Phase 22 plus a side-work atomic-refuse default-flip on migration 0019.

Purpose:
- Close Phase 22's three review-gate residuals (F1 INIT.md doc gap, F2 healthz timeout, F3 SIGTERM trap)
- Close Phase 22's one non-goal (F4 SKILL.md drift test)
- Land the user-requested `withCronMonitor` SDK-composition refactor (F5 Shape A per D-08)
- Fix migration 0019's "patches everywhere on refuse" behaviour to match migration 0017's atomic-refuse default (D-07)
- Author ADR-0029 capturing the F5 architectural decision with rejected alternatives for `/gsd-review` audit

Output:
- 14+ modified files across 4 stacks, 1 migration engine, 1 test harness, 1 ADR, SKILL.md + CHANGELOG.md
- 4 new TDD tests (F2 timeout × 1 stack × 4 stacks, F3 sigterm, F4 drift, F5 parity × 3 stacks)
- 1 new migration fixture (07-allow-partial-emits-patches)
- 1 new ADR (0029-cron-monitor-sdk-composition.md)
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/23-observability-followups/CONTEXT.md
@.planning/phases/23-observability-followups/DISCUSSION-LOG.md
@.planning/phases/22-sentry-crons-healthz/CONTEXT.md
@.planning/phases/22-sentry-crons-healthz/PLAN.md
@.planning/phases/22-sentry-crons-healthz/SECURITY.md
@./CLAUDE.md
@./AGENTS.md
@add-observability/templates/ts-cloudflare-worker/cron-monitor.ts
@add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts
@add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts
@add-observability/templates/go-fly-http/cron_monitor.go
@add-observability/templates/go-fly-http/healthz_snippet.go
@add-observability/init/INIT.md
@add-observability/SKILL.md
@migrations/run-tests.sh
@templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
@migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh

<interfaces>
<!-- Key contracts the executor needs. Extract once here to avoid scavenger hunts. -->

From add-observability/templates/ts-cloudflare-worker/cron-monitor.ts (current public surface — PRESERVED under D-08 Shape A):
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

Sentry SDK signature (Context7-verified from getsentry/sentry-javascript, packages/core/src/exports.ts; re-exported by @sentry/cloudflare):
```typescript
// withMonitor wraps callback in withIsolationScope and emits in_progress + ok/error checkins with duration tracking.
// SDK errors during captureCheckIn are RE-THROWN (this is the documented R02/R04 regression).
export function withMonitor<T>(
  slug: string,
  callback: () => T,
  monitorConfig?: MonitorConfig
): T;
```

From add-observability/templates/go-fly-http/cron_monitor.go (UNCHANGED under D-09 — doc note only):
```go
func WithCronMonitor(ctx context.Context, fn func() error, opts ...CronMonitorOption) error
```

From migrations/run-tests.sh (existing test naming convention — F3 + F4 follow same shape):
```bash
test_migration_NNNN() { ... }   # named per-migration tests
run_all() { test_migration_0001; test_migration_0005; ... }
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

From migration 0017's analogue (templates/.claude/scripts/migrate-0017-axiom-destination.sh) — D-07's reference implementation:
- Line 26-27: `* DEFAULT refuse path is atomic: not a single file is created/modified when any root is dirty (review #7 all-clean gate).`
- Migration 0017 ALREADY implements zero-side-effect-default + opt-in-patches. D-07 brings 0019 into alignment.
</interfaces>
</context>

<gitnexus_required_symbols>
<!-- Per ./CLAUDE.md: every symbol edit MUST run gitnexus_impact({target, direction: "upstream"}) BEFORE the edit and record the risk level. -->

| Task | Symbol | File | Edit shape |
|------|--------|------|------------|
| T-F2.{worker,pages,supabase} | healthzHandler | add-observability/templates/ts-{stack}/healthz-snippet.ts | wrap probe calls in AbortSignal.timeout |
| T-F2.go | HealthzHandler | add-observability/templates/go-fly-http/healthz_snippet.go | wrap probe calls in context.WithTimeout |
| T-F5.{worker,pages,supabase} | withCronMonitor | add-observability/templates/ts-{stack}/cron-monitor.ts | replace lines 148-181 with Sentry.withMonitor call |
| T-F3 | engine top-level (no apply.sh exists in repo) | templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh | add `trap 'cleanup' INT TERM EXIT` to the 2-pass engine; Task 3.1 behaviour block enumerates the exact landing spots |
| T-F3 | run_test / run_all | migrations/run-tests.sh | add trap + add `--pause-between-passes <signal-file>` test-only flag handling in the engine (NOT in a non-existent apply.sh) |
| T-D07 | emit_refuse_artifacts | templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:542-573 | gate clean-root emission on `[ "$ALLOW_PARTIAL" -eq 1 ]` |
| T-D09 | WithCronMonitor (Go) | add-observability/templates/go-fly-http/cron_monitor.go | doc-only edit to package doc preceding the function (no body change — gitnexus_impact still required per CLAUDE.md "before editing any symbol") |

Acceptance check on each task: `gitnexus_impact` was run and reported risk level. If HIGH or CRITICAL: action requires explicit "proceed-anyway" rationale in commit body. If GitNexus index is stale, run `npx gitnexus analyze` before the impact call.
</gitnexus_required_symbols>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Cron handler body → Sentry SDK | F5 changes how cron breadcrumbs/scope/user-context flow between invocations via withIsolationScope |
| Outer wrapper (withObservabilityScheduled) → withCronMonitor | F5 drops SDK-error swallow; transport errors during captureCheckIn now bubble up |
| Healthz handler → probe targets (DB, KV, upstream HTTP) | F2 introduces controlled abort; aborted probes must not leak partial state (open connections, mid-query state) |
| Migration engine → operator filesystem | F3 SIGTERM trap runs cleanup before re-raise. D-07 changes the default refuse path from "writes patches to all roots" to "writes nothing" |
| Operator interactive shell ↔ engine via SIGINT | F3's trap converts "Ctrl-C corrupts state" into "Ctrl-C cleanly aborts" |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-23-01 | I (Information disclosure) | F5 withCronMonitor + Sentry.withMonitor | mitigate | `withIsolationScope` wrapping ISOLATES scope per cron run, preventing leak of one cron's user/tags/breadcrumbs into the next. Net improvement over the current shared-isolate behaviour. ADR-0029 documents this addition. T-F5 tasks assert the addition in the parity tests by mocking `withMonitor` and confirming the callback runs once per invocation. |
| T-23-02 | D (Denial of service via unhandled exception) | F5 outer wrapper chain | mitigate | F5 drops R02/R04 SDK-error swallow — `Sentry.withMonitor` re-throws SDK transport errors during `captureCheckIn`. RISK: if `withObservabilityScheduled` (outer wrapper) does not catch, the cron handler fails when Sentry's transport is down. ACTION: T-F5.worker MUST grep the outer wrapper chain (`add-observability/templates/ts-cloudflare-worker/middleware.ts` `withObservabilityScheduled` impl) and verify it catches; if it does NOT, the executor MUST add an explicit try/catch around the `Sentry.withMonitor` call inside cron-monitor.ts that swallows SDK errors but NOT handler errors. Documented in CHANGELOG.md 0.7.0 as the R02/R04 regression with operator mitigation guidance ("set `SENTRY_DEBUG=1` to surface swallowed transport errors"). |
| T-23-03 | I (Information disclosure via timing oracle) | F2 healthz handler | mitigate | Per-probe `AbortSignal.timeout(DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS)` (TS) and `context.WithTimeout(ctx, defaultHealthzProbeTimeout)` (Go) caps each probe at 2s. Aborted probes report `"timeout"` (not `false` and not `true`), so an attacker cannot use response latency to fingerprint slow upstreams. Acceptance test in T-F2.{worker,pages,supabase,go} asserts: probe deliberately hangs > 2s → response returns within 2s + 200ms slack with `{status: "degraded", checks: {<probe>: "timeout"}}`. |
| T-23-04 | D (Denial of service via leaked resources) | F2 aborted probes | mitigate | TS: `AbortSignal.timeout` abort propagates to the probe's underlying fetch/KV/DB call IFF the probe accepts AbortSignal. T-F2 acceptance criterion: each probe call passes the signal — `env.OBSERVABILITY_KV.get("healthz-probe", { signal })` (KV does not accept signal — wrap in Promise.race), `env.SERVICE_BINDING.fetch(req, { signal })`. Probes that genuinely cannot accept signal MUST be wrapped in `Promise.race([probe(), abortable()])` so the handler unblocks even if the probe call doesn't honour the abort. Go: `db.PingContext(ctx)` and a new `req.WithContext(ctx)` on the upstream Get already honour ctx cancellation; no leaked goroutines. Test: probe hangs 5s; verify response returns within 2.2s; verify no open handle accumulation across 100 sequential degraded responses (mock-instrumented). |
| T-23-05 | T (Tampering with engine state via signal) | F3 SIGTERM trap | mitigate | `cleanup` MUST be idempotent (callable from EXIT trap AND from explicit early-exit). Cleanup MUST NOT print env vars, secrets, or partial canonical-file contents to stderr. Test t-sigterm asserts: SIGTERM mid-pass-2 → trap fires → no half-written canonical file → re-run succeeds → cleanup stderr contains no `SENTRY_DSN=` or `ALLOW_PARTIAL=` echoes. T-F3 acceptance: `grep -E '(SENTRY_DSN|API_KEY|TOKEN)=' <captured_stderr>` returns empty. |
| T-23-06 | E (Elevation of privilege via flag misuse) | D-07 --allow-partial default flip | accept | Operators who relied on R09 "patches everywhere on refuse" must explicitly opt in via `--allow-partial` or `ALLOW_PARTIAL=true`. RISK: a downstream automation that previously assumed clean-root patches on refuse now sees none. MITIGATION: CHANGELOG.md 0.7.0 explicitly documents the default-flip + the opt-in flag. Migration runbook footnote (in `add-observability/uptime-setup-runbook.md` OR a new note in the migration 0019 markdown) tells operators with existing automation to add `--allow-partial`. Disposition: ACCEPT — the previous behaviour was the bug; D-07 restores the documented "truly atomic refusal" invariant. |
| T-23-07 | S (Spoofing via test-only flag in production) | F3 --pause-between-passes flag | mitigate | The `--pause-between-passes <signal-file>` flag is test-only. Production code path must reject it OR document it as test-internal. ACTION: when present, the flag MUST log a warning to stderr ("--pause-between-passes is a test-only flag; do not use in production") AND require the signal-file argument to be inside `$REPO_ROOT/migrations/test-fixtures/` OR `$TMPDIR` (reject otherwise with exit 2). Tests in `migrations/run-tests.sh` use a signal file in `$TMPDIR`. Acceptance: passing `--pause-between-passes /etc/passwd` exits 2 with "test-only flag with non-fixture path"; passing `--pause-between-passes "$TMPDIR/sig"` proceeds. |

Severity gating: T-23-02 (D), T-23-04 (D), T-23-05 (T), T-23-07 (S) are MEDIUM. T-23-01 (I) is LOW. T-23-03 (I) is LOW (post-mitigation). T-23-06 (E) is ACCEPTED — documented operator-facing change. No HIGH or CRITICAL threats remain post-mitigation. Phase proceeds.
</threat_model>

<tasks>

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 1 — parallel-safe; independent files, no shared state              -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto">
  <name>Task 1.1 (Wave 1, F1): INIT.md per-stack Phase 5 composition notes</name>
  <files>add-observability/init/INIT.md</files>
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
    3. Link to the wrapper source file with a relative file:line link of the form `templates/{stack}/cron-monitor.{ts,go}:<line-of-`withCronMonitor`-export>`

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
      grep -q "templates/go-fly-http/cron_monitor.go:" add-observability/init/INIT.md &&
      ! grep -q "withCronMonitor" add-observability/init/INIT.md.bak 2>/dev/null  # ensure new content (only if bak made)
    </automated>
  </verify>
  <done>
    INIT.md Phase 5 has 4 stack subsections each citing withCronMonitor with a templates/{stack}/cron-monitor.{ts,go}:<line> link; react-vite subsection unchanged.
  </done>
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
      grep -q "sentry-go.*no.*WithMonitor" add-observability/templates/go-fly-http/cron_monitor.go &&
      diff <(sed -n '225,270p' add-observability/templates/go-fly-http/cron_monitor.go) <(git show HEAD:add-observability/templates/go-fly-http/cron_monitor.go | sed -n '225,270p')  # symbol body unchanged
    </automated>
  </verify>
  <done>
    Package doc block contains the ≤5-line D-09 note immediately before the package declaration; function body unchanged.
  </done>
  <acceptance_criteria>
    - The literal phrase "SDK gap (D-09" appears in the file
    - The phrase "sentry-go" appears with "no" and "WithMonitor" near it (regex above)
    - `WithCronMonitor` function body (lines 225-270 in pre-edit file) byte-identical to HEAD
    - gitnexus_impact was run; report risk level (likely LOW for doc-only edit)
    - Commit: `docs(23): D-09 document sentry-go WithMonitor SDK gap in cron_monitor.go`
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 1.3 (Wave 1, F4): SKILL.md drift test (TDD red-green)</name>
  <files>migrations/run-tests.sh, skill/SKILL.md (temporarily for RED)</files>
  <read_first>
    - migrations/run-tests.sh (full file — locate run_all() and add the new test there)
    - skill/SKILL.md lines 1-15 (frontmatter format that D-04's parser targets)
    - migrations/0019-sentry-crons-and-healthz.md lines 1-10 (frontmatter format showing `to_version:` field — this is what the test compares against)
    - .planning/phases/23-observability-followups/CONTEXT.md D-04 (minimal bash parser, no yq) and D-06 (test lives in run-tests.sh) and G4
  </read_first>
  <behavior>
    Per D-06, add a new test function in `migrations/run-tests.sh` named exactly: `test-skill-md-version-matches-latest-migration-to-version` (kebab-case in the printed name; bash function name `test_skill_md_version_matches_latest_migration_to_version` to match repo convention).

    The test:
    1. Extracts `skill/SKILL.md` version using D-04's minimal parser: `grep ^version: skill/SKILL.md | awk '{print $2}'` (one line each)
    2. Finds the highest-numbered file in `migrations/` matching `[0-9][0-9][0-9][0-9]-*.md` (use `ls migrations/[0-9][0-9][0-9][0-9]-*.md | sort | tail -1`)
    3. Extracts that file's `to_version:` field using the SAME parser: `grep ^to_version: <file> | awk '{print $2}'`
    4. Asserts equality; on mismatch, prints `FAIL: SKILL.md at vX.Y.Z but migration NNNN declares to_version: vA.B.C` and increments FAIL

    RED phase: temporarily desync skill/SKILL.md to version `1.99.0`; run `migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version`; assert exit code ≠ 0 and stderr contains the FAIL message above.

    GREEN phase: restore skill/SKILL.md version; run the same command; assert exit code 0 and stdout contains `PASS: test-skill-md-version-matches-latest-migration-to-version`.
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "run_all", direction: "upstream"})` on migrations/run-tests.sh's test runner; record risk.

    **RED commit** (commit message `test(23): F4 SKILL.md drift test — RED`):
    1. Add the bash function `test_skill_md_version_matches_latest_migration_to_version` to migrations/run-tests.sh. The function MUST:
       - Use only `grep`, `awk`, `ls`, `sort`, `tail` (no `yq`, no `python`, no `jq`)
       - Print exactly `FAIL: SKILL.md at v<skill_version> but migration <NNNN> declares to_version: v<migration_version>` on mismatch
       - Increment global `FAIL` counter and use the same PASS/FAIL/SKIP color scheme as sibling tests
       - Be registered in `run_all()` alongside the other `test_migration_NNNN` calls — append the call after the highest existing `test_migration_NNNN` reference
       - Support being run standalone via `migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version` (per FILTER parsing logic at line 60-69 of run-tests.sh)
    2. Temporarily edit skill/SKILL.md line 3 from `version: 1.18.0` to `version: 1.99.0` (RED state — DO NOT commit this skill/SKILL.md edit)
    3. Run `migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version 2>&1 | tee /tmp/red-output.txt`
    4. Assert: exit code is non-zero AND `grep -q "FAIL: SKILL.md at v1.99.0 but migration .* declares to_version: v1.18.0" /tmp/red-output.txt`
    5. Revert skill/SKILL.md to `version: 1.18.0`
    6. Commit migrations/run-tests.sh changes ONLY (skill/SKILL.md is back to original — not in the commit)

    **GREEN commit** (commit message `feat(23): F4 SKILL.md drift test passes against current versions — GREEN`):
    1. Run `migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version 2>&1 | tee /tmp/green-output.txt`
    2. Assert: exit code 0 AND `grep -q "PASS.*test-skill-md-version-matches-latest-migration-to-version" /tmp/green-output.txt`
    3. Commit message body MUST document: "RED→GREEN pair for D-06 / G4. Parser per D-04: grep + awk only, no yq dep."
    4. The GREEN commit may be empty if RED already left the test in passing state — use `git commit --allow-empty` with the documented message. (This is the documentation of the test going from failing to passing without code change because the production state already matches.)
  </action>
  <verify>
    <automated>
      bash migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version &&
      grep -q "test_skill_md_version_matches_latest_migration_to_version" migrations/run-tests.sh &&
      ! grep -q "yq " migrations/run-tests.sh  # no yq dep introduced
    </automated>
  </verify>
  <done>
    RED commit pushed test, ran the test against desynced SKILL.md, captured FAIL message. GREEN commit ran the test against current SKILL.md and passes. Test uses only grep + awk; no yq.
  </done>
  <acceptance_criteria>
    - Test function name in bash: `test_skill_md_version_matches_latest_migration_to_version` (greppable)
    - Filter name (CLI arg): `test-skill-md-version-matches-latest-migration-to-version` (kebab-case, exactly as D-06 specifies)
    - `grep -E "yq |yq\\$" migrations/run-tests.sh` returns no new occurrences (D-04 compliance)
    - RED commit log shows the test failed with the documented FAIL message when SKILL.md was desynced
    - GREEN commit log shows the test passing
    - Test registered in `run_all()` — appears in the function call list near the bottom of run-tests.sh
    - gitnexus_impact run on `run_all`; risk level recorded
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 1.4 (Wave 1, F2.worker): healthz per-probe timeout — TS Cloudflare Worker (TDD)</name>
  <files>add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts, add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts</files>
  <read_first>
    - add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts (full file — F2 wraps each probe; preserve R06 fail-closed)
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts (existing test conventions — vitest, vi.mock, fakeController pattern; healthz tests follow same style)
    - .planning/phases/23-observability-followups/CONTEXT.md D-03 (DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS=2000, caller-configurable, degraded JSON with `"timeout"` sentinel)
    - .planning/phases/22-sentry-crons-healthz/SECURITY.md §S4 (the original timeout-oracle finding)
  </read_first>
  <behavior>
    Test cases for healthz-snippet.test.ts (new file):

    - **Test 1 (RED first)**: probe that resolves quickly (10ms) → returns `{status: "ok", checks: {kv: true}}` within timeout. Asserts the happy path is unchanged.
    - **Test 2 (RED first)**: probe that hangs > 2000ms → response returns within 2200ms (2000ms timeout + 200ms slack) with `{status: "degraded", checks: {kv: "timeout"}}` — NOTE: `"timeout"` is a STRING (not boolean false), distinguishing timeout from genuine probe failure per D-03.
    - **Test 3 (RED first)**: caller passes a custom timeout via `healthzHandler(req, env, { probeTimeoutMs: 500 })` — probe hanging 1000ms aborts at 500ms.
    - **Test 4**: pre-existing behaviour — handler keeps R06 (zero-probes-configured → 503 + reason). Re-assert.

    Test handler probe shape must use `vi.fn` mocks that accept `AbortSignal` and respect abort (mock-side: race the configured probe latency against the signal's `abort` event).
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "healthzHandler", direction: "upstream"})` on the worker healthz-snippet; record risk.

    **RED commit** (`test(23): F2 worker healthz per-probe timeout — RED`):
    1. Create `add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts` following the vitest pattern from cron-monitor.test.ts:
       - `import { describe, it, expect, vi, beforeEach } from "vitest";`
       - `import { healthzHandler } from "./healthz-snippet";`
       - 4 tests per `<behavior>` block above
       - Use `AbortSignal` in mocks; test 2's hanging probe uses `new Promise((_resolve, reject) => signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))))` shape
    2. Run `cd add-observability/templates/ts-cloudflare-worker && npx vitest run healthz-snippet.test.ts 2>&1 | tee /tmp/red-f2-worker.txt`
    3. Assert: tests 2 and 3 FAIL (production code doesn't yet honour timeouts). Tests 1 and 4 may pass.
    4. Commit test file ONLY.

    **GREEN commit** (`feat(23): F2 worker healthz per-probe timeout — GREEN`):
    1. Modify `add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts`:
       a. Add an exported constant at top of file (after the WARNING block, before `// ─── Public types`):
          ```typescript
          /** D-03 default per-probe timeout in ms; override via healthzHandler 3rd arg. */
          export const DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000;
          ```
       b. Add optional 3rd parameter to `healthzHandler`:
          ```typescript
          export async function healthzHandler(
            _req: Request,
            env: HealthzEnv,
            opts?: { probeTimeoutMs?: number },
          ): Promise<Response>
          ```
       c. Inside the function, replace `const checks: Record<string, boolean> = {};` with `const checks: Record<string, boolean | "timeout"> = {};`
       d. Compute `const probeTimeoutMs = opts?.probeTimeoutMs ?? DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS;` at top of function body
       e. Wrap EACH probe body in a Promise.race or AbortSignal-based timeout. Shape per probe:
          ```typescript
          if (env.OBSERVABILITY_KV) {
            const signal = AbortSignal.timeout(probeTimeoutMs);
            try {
              await Promise.race([
                env.OBSERVABILITY_KV.get("healthz-probe"),
                new Promise<never>((_r, reject) => {
                  signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
                }),
              ]);
              checks.kv = true;
            } catch (e) {
              checks.kv = (e instanceof DOMException && e.name === "AbortError") ? "timeout" : false;
            }
          }
          ```
          Apply the same shape to the `SERVICE_BINDING` probe; pass `signal` to fetch via `new Request("https://internal/healthz", { signal })`.
       f. Update the final JSON-encoding `allOk` calculation to treat `"timeout"` as falsy: `const allOk = probeNames.every((k) => checks[k] === true);`
    2. Run `npx vitest run healthz-snippet.test.ts 2>&1 | tee /tmp/green-f2-worker.txt`
    3. Assert: ALL 4 tests pass; exit code 0.
    4. Commit production file.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-cloudflare-worker && npx vitest run healthz-snippet.test.ts &&
      grep -q "DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000" add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts &&
      grep -q "AbortSignal.timeout\\|abort" add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts &&
      grep -q '"timeout"' add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts
    </automated>
  </verify>
  <done>
    RED→GREEN pair; timeout-degraded test passes; `DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000` constant exported; per-probe AbortSignal.timeout wired; `"timeout"` string sentinel in checks output.
  </done>
  <acceptance_criteria>
    - vitest reports 4/4 tests passing on healthz-snippet.test.ts
    - File contains literal `DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000`
    - File contains literal `AbortSignal.timeout(`
    - File contains literal `"timeout"` (the string sentinel for the degraded check value)
    - R06 fail-closed path (zero probes) test still passes
    - RED commit log + GREEN commit log preserved
    - gitnexus_impact on `healthzHandler` recorded
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 1.5 (Wave 1, F2.pages): healthz per-probe timeout — TS Cloudflare Pages (TDD)</name>
  <files>add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts, add-observability/templates/ts-cloudflare-pages/healthz-snippet.test.ts</files>
  <read_first>
    - add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts (the file being modified)
    - add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts (just-edited reference — pages mirrors worker shape)
    - add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts (the test file from Task 1.4 — pages mirrors)
    - .planning/phases/23-observability-followups/CONTEXT.md D-03
  </read_first>
  <behavior>
    Identical 4-test shape as Task 1.4 (TS worker), adapted to the pages stack's probe interface. If pages's healthz-snippet.ts probe-name set differs from worker's, adapt the mock targets accordingly.
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "healthzHandler", direction: "upstream"})` on the pages healthz-snippet; record risk.

    Mirror Task 1.4 for the pages stack. Concrete substrings to add to the production file (verbatim):
    - `export const DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000;`
    - `AbortSignal.timeout(probeTimeoutMs)`
    - `"timeout"` string sentinel in checks
    - `opts?: { probeTimeoutMs?: number }` 3rd handler parameter
    Apply per-probe Promise.race or signal-listener pattern from Task 1.4.

    RED commit `test(23): F2 pages healthz per-probe timeout — RED`; GREEN commit `feat(23): F2 pages healthz per-probe timeout — GREEN`.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-cloudflare-pages && npx vitest run healthz-snippet.test.ts &&
      grep -q "DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000" add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts
    </automated>
  </verify>
  <done>RED→GREEN pair for pages stack; behaviour mirrors worker.</done>
  <acceptance_criteria>
    - 4/4 vitest tests pass on pages healthz-snippet.test.ts
    - All literal-string acceptance criteria from Task 1.4 also hold for pages file
    - gitnexus_impact recorded
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 1.6 (Wave 1, F2.supabase): healthz per-probe timeout — TS Supabase Edge (TDD)</name>
  <files>add-observability/templates/ts-supabase-edge/healthz-snippet.ts, add-observability/templates/ts-supabase-edge/healthz-snippet.test.ts</files>
  <read_first>
    - add-observability/templates/ts-supabase-edge/healthz-snippet.ts (the file being modified)
    - add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts (reference)
    - .planning/phases/23-observability-followups/CONTEXT.md D-03
  </read_first>
  <behavior>
    Identical 4-test shape, adapted to supabase-edge probe interface (probes use Deno fetch; if the existing probe shape uses `Deno.serve`-style or a Supabase client, mirror that mock).
  </behavior>
  <action>
    [BLOCKING] gitnexus_impact on healthzHandler (supabase variant).

    Mirror Task 1.4. Add `DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000` constant, optional `probeTimeoutMs` parameter, per-probe AbortSignal.timeout, `"timeout"` sentinel.

    RED `test(23): F2 supabase-edge healthz per-probe timeout — RED`; GREEN `feat(23): F2 supabase-edge healthz per-probe timeout — GREEN`.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-supabase-edge && npx vitest run healthz-snippet.test.ts &&
      grep -q "DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000" add-observability/templates/ts-supabase-edge/healthz-snippet.ts
    </automated>
  </verify>
  <done>RED→GREEN pair for supabase-edge stack.</done>
  <acceptance_criteria>
    - 4/4 vitest tests pass on supabase-edge healthz-snippet.test.ts
    - All literal-string acceptance criteria from Task 1.4 also hold
    - gitnexus_impact recorded
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 1.7 (Wave 1, F2.go): healthz per-probe timeout — Go fly-http (TDD)</name>
  <files>add-observability/templates/go-fly-http/healthz_snippet.go, add-observability/templates/go-fly-http/healthz_snippet_test.go</files>
  <read_first>
    - add-observability/templates/go-fly-http/healthz_snippet.go (full file — HealthzHandler currently has no per-probe timeout)
    - .planning/phases/23-observability-followups/CONTEXT.md D-03 (Go uses `context.WithTimeout(ctx, defaultHealthzProbeTimeout)` where `defaultHealthzProbeTimeout = 2 * time.Second`)
  </read_first>
  <behavior>
    Equivalent test shape to Task 1.4 in Go:
    - Test 1: fast probe → 200 + `{"status":"ok","checks":{"db":true}}`
    - Test 2: hanging probe → 503 + `{"status":"degraded","checks":{"db":"timeout"}}` within 2.2s (default 2s + 200ms slack)
    - Test 3: caller passes custom timeout via a new exported `HealthzDeps.ProbeTimeout time.Duration` field; probe hanging 1s aborts at 500ms.
    - Test 4: R06 zero-probes path still returns degraded JSON unchanged.

    Use `testing.T`, `httptest.NewRecorder()`, `httptest.NewRequest`. Mock `dbProbe` with a struct that sleeps then returns nil, but honours ctx.Done().
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "HealthzHandler", direction: "upstream"})` on Go healthz_snippet.go; record risk.

    **RED commit** (`test(23): F2 go healthz per-probe timeout — RED`):
    1. Create `add-observability/templates/go-fly-http/healthz_snippet_test.go`:
       ```go
       package {{PACKAGE_NAME}}  // replaced with `observability` for the in-template test

       // NOTE: in shipped templates, the package name is substituted at init time.
       // For unit testing, replace with `package observability` inside the
       // template's local test harness; the run-template-tests.sh harness handles this.

       import (
         "context"
         "encoding/json"
         "net/http"
         "net/http/httptest"
         "testing"
         "time"
       )

       type slowDB struct{ delay time.Duration }
       func (s *slowDB) PingContext(ctx context.Context) error {
         select { case <-time.After(s.delay): return nil; case <-ctx.Done(): return ctx.Err() }
       }

       // Tests 1-4 per <behavior>.
       ```
       Implement all 4 tests.
    2. Run `cd add-observability/templates/go-fly-http && go test -run "TestHealthz" -count=1 ./... 2>&1 | tee /tmp/red-f2-go.txt`
    3. Assert: tests 2 and 3 FAIL.
    4. Commit test file ONLY.

    **GREEN commit** (`feat(23): F2 go healthz per-probe timeout — GREEN`):
    1. Modify healthz_snippet.go:
       a. Add to imports: `"time"`
       b. Add exported constant after imports, before `// ─── Probe interfaces`:
          ```go
          // DefaultHealthzProbeTimeout is the D-03 default per-probe timeout. Override
          // per HealthzDeps.ProbeTimeout (zero value = default).
          const defaultHealthzProbeTimeout = 2 * time.Second
          ```
       c. Add to `HealthzDeps`:
          ```go
          // ProbeTimeout overrides the per-probe timeout (D-03). Zero = defaultHealthzProbeTimeout.
          ProbeTimeout time.Duration
          ```
       d. Change `checks` type from `map[string]bool{}` to `map[string]any{}` so a probe can store either `true`, `false`, or the string `"timeout"`.
       e. Inside the handler body:
          ```go
          probeTimeout := deps.ProbeTimeout
          if probeTimeout == 0 { probeTimeout = defaultHealthzProbeTimeout }
          ```
       f. For the DB probe, wrap in `context.WithTimeout(r.Context(), probeTimeout)`:
          ```go
          if deps.DB != nil {
            ctx, cancel := context.WithTimeout(r.Context(), probeTimeout)
            err := deps.DB.PingContext(ctx)
            cancel()
            switch {
            case err == nil:
              checks["db"] = true
            case err == context.DeadlineExceeded:
              checks["db"] = "timeout"
            default:
              checks["db"] = false
            }
          }
          ```
       g. Apply the same shape to the Upstream probe. Note: `upstreamProbe.Get` does not accept ctx — wrap in a goroutine + channel + select-on-ctx.Done. The upstreamProbe interface stays compatible (no signature change), but the handler implementation does the timing.
       h. Adjust the `allOK` loop to treat any non-`true` value as failure:
          ```go
          allOK := true
          for _, v := range checks {
            if v != true { allOK = false; break }
          }
          ```
    2. Run `go test -run "TestHealthz" -count=1 ./... 2>&1 | tee /tmp/green-f2-go.txt`
    3. Assert: all 4 tests pass.
    4. Commit production file.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/go-fly-http && go test -run "TestHealthz" -count=1 ./... &&
      grep -q "defaultHealthzProbeTimeout = 2 \\* time.Second" add-observability/templates/go-fly-http/healthz_snippet.go &&
      grep -q "context.WithTimeout" add-observability/templates/go-fly-http/healthz_snippet.go &&
      grep -q '"timeout"' add-observability/templates/go-fly-http/healthz_snippet.go
    </automated>
  </verify>
  <done>RED→GREEN pair; Go healthz handler honours per-probe context-based timeout; `defaultHealthzProbeTimeout = 2 * time.Second` constant declared.</done>
  <acceptance_criteria>
    - All 4 Go tests pass
    - `defaultHealthzProbeTimeout = 2 * time.Second` literal present
    - `context.WithTimeout` literal present (per-probe usage)
    - `"timeout"` string sentinel in checks output
    - R06 fail-closed path still returns 503 + reason on zero probes
    - gitnexus_impact on `HealthzHandler` recorded
  </acceptance_criteria>
</task>

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 2 — F5 Shape A refactor, one task per TS stack (parallel-safe)     -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto" tdd="true">
  <name>Task 2.1 (Wave 2, F5.worker): withCronMonitor Shape A — TS Cloudflare Worker (TDD)</name>
  <files>add-observability/templates/ts-cloudflare-worker/cron-monitor.ts, add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts</files>
  <read_first>
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts FULL FILE (lines 137-148 PRESERVED; 148-181 REPLACED — read carefully)
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts FULL FILE (existing test conventions; F5 tests extend the same describe-blocks)
    - .planning/phases/23-observability-followups/CONTEXT.md D-08 (Shape A spec: exact line-range substitution)
    - .planning/phases/23-observability-followups/CONTEXT.md §"Resolved decisions" — DOCUMENTED REGRESSION (R02/R04 SDK-error swallow drops) and DOCUMENTED ADDITION (withIsolationScope wrapping)
    - .planning/phases/22-sentry-crons-healthz/PLAN.md §R02, §R04 (the contracts being regressed)
    - .planning/phases/22-sentry-crons-healthz/CONTEXT.md D6, D11, D12 (the contracts being PRESERVED)
    - add-observability/templates/ts-cloudflare-worker/middleware.ts (outer wrapper — verify it catches SDK errors so the documented R02/R04 regression doesn't fail the cron when Sentry transport is down; see T-23-02 in threat model)
  </read_first>
  <behavior>
    Behavioural-parity test cases for cron-monitor.test.ts (EXTEND, do not replace existing tests):

    - **Test F5.1 (RED first)**: happy path with explicit slug — assert `Sentry.withMonitor` is called ONCE with arguments matching `("fxsa-ingest-15min", <callback function>, undefined)` (no monitorConfig configured). Assert `captureCheckIn` is NOT called directly from the wrapper (it's called from inside `withMonitor` which is mocked).
    - **Test F5.2 (RED first)**: with `schedule` + `maxRuntimeSeconds` config — assert `Sentry.withMonitor` is called with `(slug, callback, {schedule: {...}, maxRuntime: 240})` (D12 monitorConfig forwarding preserved through Shape A).
    - **Test F5.3 (RED first)**: handler throws — assert `Sentry.withMonitor`'s thrown rejection propagates and the outer wrapper's caller sees the exception (D-08 documented behaviour: errors propagate; no SDK-error swallow on the wrapper's own scope).
    - **Test F5.4 (RED first)**: SENTRY_DSN unset — assert handler runs unchanged AND `Sentry.withMonitor` is NOT called (fail-safe per R02 PRESERVED via the if-isConfigured guard at line 138).
    - **Test F5.5 (RED first — D6 slug resolution)**: extend existing "slug resolution" describe-block to assert the slug computed by `resolveSlug` is the slug passed to `Sentry.withMonitor` (preserves D6).
    - **Modify** existing tests "emits in_progress + ok on happy path" and "emits in_progress + error and re-throws on handler exception": these assert `captureCheckIn` directly. Under Shape A, the wrapper no longer calls `captureCheckIn` — `Sentry.withMonitor` does internally, but our mock at the module boundary will only see `withMonitor`. Update these tests to either: (a) DELETE them and replace with the F5.1-F5.5 cases above, OR (b) re-mock `withMonitor` to forward to `captureCheckIn` internally to keep the existing assertions valid. Recommend option (a) — the v0.6.0 tests asserted implementation details that Shape A obsoletes. Update the test file's docblock at lines 1-17 to reference D-08 instead of the v0.6.0 contract.
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "withCronMonitor", direction: "upstream"})` on cron-monitor.ts; record risk. Per ./CLAUDE.md this is BLOCKING for symbol body edits and the risk level MUST be reported to the user via the commit body. If HIGH or CRITICAL: include explicit "proceed-anyway" rationale referencing D-08's user authorization.

    Also: grep `withCronMonitor` callers across the repo and across the documented downstream consumers (fxsa, callbot per CONTEXT.md). The PR will land in claude-workflow only; downstream pulls via the add-observability minor bump. Document any consumers found.

    Also: read `add-observability/templates/ts-cloudflare-worker/middleware.ts` and verify `withObservabilityScheduled` catches SDK errors (per T-23-02). If it does NOT, add an explicit catch around `Sentry.withMonitor` in cron-monitor.ts that swallows SDK transport errors only (not handler errors). Document the verdict in the commit body.

    **RED commit** (`test(23): F5 worker Shape A behavioural-parity — RED`):
    1. Update cron-monitor.test.ts to mock `Sentry.withMonitor`:
       ```typescript
       const withMonitorMock = vi.fn();
       const captureCheckIn = vi.fn();  // kept for the no-call assertion
       vi.mock("@sentry/cloudflare", () => ({
         captureCheckIn: (...args: unknown[]) => captureCheckIn(...args),
         withMonitor: (...args: unknown[]) => withMonitorMock(...args),
       }));
       ```
       Default mock behaviour: `withMonitorMock.mockImplementation(async (_slug, cb) => cb());` (immediate callback exec). Override per-test for the throw case.
    2. Replace old happy-path / error-path / DEBUG-log tests with the F5.1-F5.5 cases per `<behavior>`. Preserve the existing slug-resolution (D6) describe-block but augment per F5.5.
    3. Update the test file's top-comment (lines 1-17) to reference D-08 and the documented regression.
    4. Run `cd add-observability/templates/ts-cloudflare-worker && npx vitest run cron-monitor.test.ts 2>&1 | tee /tmp/red-f5-worker.txt`
    5. Assert: F5.1, F5.2, F5.3 FAIL (production code still calls captureCheckIn directly). F5.4 may pass (no-DSN guard is unchanged). F5.5 may pass partially.
    6. Commit test file ONLY.

    **GREEN commit** (`feat(23): F5 worker Shape A — replace lifecycle with Sentry.withMonitor — GREEN`):
    1. Modify `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts`:
       a. Change import: `import { captureCheckIn } from "@sentry/cloudflare";` → `import * as Sentry from "@sentry/cloudflare";` (so the impl can call `Sentry.withMonitor(...)`)
       b. PRESERVE lines 137-148 (the wrapper's outer function body up to and including `const monitorConfig = buildMonitorConfig(config);`)
       c. REPLACE lines 148-181 (the entire in_progress/ok/error lifecycle block) with EXACTLY:
          ```typescript
              // D-08 Shape A — compose Sentry.withMonitor underneath outer wrapper.
              // PRESERVED: D6 slug resolution (above), R02 fail-safe (above), D12 monitorConfig forwarding (above).
              // REGRESSED (vs v0.6.0): R02/R04 SDK-error swallow drops — Sentry.withMonitor re-throws
              //   transport errors during captureCheckIn instead of silently swallowing. Operators see
              //   them in the outer withObservabilityScheduled capture path. SENTRY_DEBUG=1 surfaces
              //   them; outer wrapper catches them per Phase 23 T-23-02 verification.
              // ADDED: withIsolationScope wrapping — each cron run gets its own Sentry scope
              //   (correctness improvement; non-breaking for downstream consumers).
              await Sentry.withMonitor(monitorSlug, () => handler(controller, env, ctx), monitorConfig);
            };
          }
          ```
       d. DELETE the `debugLog` helper function declaration (lines 102-112 in the pre-edit file) AND its `isDebug` helper (lines 50-52) — they are no longer used. Search the file for any remaining references; if `SENTRY_DEBUG` is referenced elsewhere in the same file, restore the helpers; otherwise delete.
       e. Update the wrapper's JSDoc (lines 116-132) to reflect Shape A:
          - Replace "SDK exceptions during checkin are caught and swallowed; opt-in `SENTRY_DEBUG=1` surfaces them via `console.error`." with: "SDK exceptions during checkin propagate via `Sentry.withMonitor` to the outer `withObservabilityScheduled` capture path (D-08 documented regression vs v0.6.0)."
          - Add line: "Each invocation runs inside its own `withIsolationScope` (D-08 documented addition)."
    2. Run `npx vitest run cron-monitor.test.ts 2>&1 | tee /tmp/green-f5-worker.txt`
    3. Assert: ALL F5.1-F5.5 + preserved D6 tests pass.
    4. Run the FULL template test harness for the worker stack: `cd add-observability/templates/ts-cloudflare-worker && npx vitest run 2>&1 | tee /tmp/green-f5-worker-all.txt` — assert: zero regressions in healthz tests (Wave 1 task 1.4).
    5. Commit production file.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-cloudflare-worker && npx vitest run cron-monitor.test.ts &&
      grep -q "Sentry.withMonitor(monitorSlug" add-observability/templates/ts-cloudflare-worker/cron-monitor.ts &&
      grep -q "D-08 Shape A" add-observability/templates/ts-cloudflare-worker/cron-monitor.ts &&
      ! grep -q "debugLog\\|isDebug" add-observability/templates/ts-cloudflare-worker/cron-monitor.ts  # helpers removed
    </automated>
  </verify>
  <done>
    RED→GREEN pair. Worker cron-monitor.ts composes `Sentry.withMonitor`. Lines 137-148 preserved. Lines 148-181 replaced. Tests assert (slug, callback, monitorConfig) signature and no direct captureCheckIn calls from the wrapper.
  </done>
  <acceptance_criteria>
    - vitest reports all cron-monitor.test.ts + healthz-snippet.test.ts tests passing
    - cron-monitor.ts contains the literal string `Sentry.withMonitor(monitorSlug`
    - cron-monitor.ts contains the literal string `D-08 Shape A`
    - cron-monitor.ts NO LONGER contains `debugLog` or `isDebug` (unless retained for other usage — document why if retained)
    - Pre-existing `resolveSlug` and `buildMonitorConfig` functions byte-identical to HEAD (D6 + D12 preservation)
    - The middleware.ts verification verdict (does outer catch SDK errors?) recorded in commit body
    - gitnexus_impact run; risk level + downstream caller list recorded in commit body
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 2.2 (Wave 2, F5.pages): withCronMonitor Shape A — TS Cloudflare Pages (TDD)</name>
  <files>add-observability/templates/ts-cloudflare-pages/cron-monitor.ts, add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts</files>
  <read_first>
    - add-observability/templates/ts-cloudflare-pages/cron-monitor.ts FULL FILE
    - add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts FULL FILE
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts (just-edited GREEN reference)
    - .planning/phases/23-observability-followups/CONTEXT.md D-08
  </read_first>
  <behavior>
    Identical F5.1-F5.5 test shape as Task 2.1 (worker), adapted to the pages-stack's wrapper signature if it diverges. If pages's cron-monitor.ts is byte-identical to worker's (apart from the file path), mirror exactly.
  </behavior>
  <action>
    [BLOCKING] gitnexus_impact on pages `withCronMonitor` symbol.

    Mirror Task 2.1 for the pages stack. Same Shape A substitution: preserve "lines 137-148 equivalent" (the fail-safe + slug + monitorConfig build), replace "lines 148-181 equivalent" (the lifecycle) with the same `Sentry.withMonitor(monitorSlug, () => handler(controller, env, ctx), monitorConfig)` call + same JSDoc updates + same helper removal.

    Same RED + GREEN commit shape; commits use `pages` in the scope label.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-cloudflare-pages && npx vitest run cron-monitor.test.ts &&
      grep -q "Sentry.withMonitor(monitorSlug" add-observability/templates/ts-cloudflare-pages/cron-monitor.ts &&
      grep -q "D-08 Shape A" add-observability/templates/ts-cloudflare-pages/cron-monitor.ts
    </automated>
  </verify>
  <done>RED→GREEN pair for pages stack; Shape A composition matches worker.</done>
  <acceptance_criteria>
    - All cron-monitor.test.ts tests pass
    - Same literal-string criteria as Task 2.1 hold
    - gitnexus_impact recorded
  </acceptance_criteria>
</task>

<task type="auto" tdd="true">
  <name>Task 2.3 (Wave 2, F5.supabase): withCronMonitor Shape A — TS Supabase Edge (TDD)</name>
  <files>add-observability/templates/ts-supabase-edge/cron-monitor.ts, add-observability/templates/ts-supabase-edge/cron-monitor.test.ts</files>
  <read_first>
    - add-observability/templates/ts-supabase-edge/cron-monitor.ts FULL FILE
    - add-observability/templates/ts-supabase-edge/cron-monitor.test.ts FULL FILE
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts (reference)
    - .planning/phases/23-observability-followups/CONTEXT.md D-08
  </read_first>
  <behavior>
    Identical F5.1-F5.5 test shape as Tasks 2.1/2.2, adapted to supabase-edge's wrapper signature. If supabase-edge imports from `@sentry/deno` instead of `@sentry/cloudflare`, adapt the mock import path accordingly; the `Sentry.withMonitor` SDK surface is identical (re-exported from @sentry/core in all three SDKs per the Context7 lookup).
  </behavior>
  <action>
    [BLOCKING] gitnexus_impact on supabase-edge `withCronMonitor` symbol.

    Mirror Task 2.1. Same Shape A line-range substitution. If `@sentry/deno` is the import source, verify it exports `withMonitor` (Context7-confirmed equivalent in @sentry/javascript core; Deno SDK re-exports from same core). If absent, fail loudly and surface as a CHECKPOINT for orchestrator escalation.
  </action>
  <verify>
    <automated>
      cd add-observability/templates/ts-supabase-edge && npx vitest run cron-monitor.test.ts &&
      grep -q "Sentry.withMonitor(monitorSlug" add-observability/templates/ts-supabase-edge/cron-monitor.ts
    </automated>
  </verify>
  <done>RED→GREEN pair for supabase-edge stack.</done>
  <acceptance_criteria>
    - All cron-monitor.test.ts tests pass
    - Literal-string criteria from Task 2.1 hold for supabase-edge file
    - If `@sentry/deno` doesn't export `withMonitor`, executor escalates instead of silently shimming
    - gitnexus_impact recorded
  </acceptance_criteria>
</task>

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 3 — F3 SIGTERM trap (sequential — trap insertion in engine + harness changes) -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto" tdd="true">
  <name>Task 3.1 (Wave 3, F3): SIGTERM trap + --pause-between-passes flag + test (TDD)</name>
  <files>migrations/run-tests.sh, templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh (no top-level migrations/apply.sh exists — see behaviour block)</files>
  <read_first>
    - migrations/run-tests.sh FULL FILE (existing run_all + test registration pattern)
    - migrations/0019-sentry-crons-and-healthz.md (canonical 2-pass migration shape; the test exercises this engine)
    - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh (the actual 2-pass implementation — the trap lands here AND/OR in a wrapper apply.sh)
    - .planning/phases/23-observability-followups/CONTEXT.md D-05 (--pause-between-passes <signal-file> test-only flag spec)
    - .planning/phases/22-sentry-crons-healthz/SECURITY.md §S6 (the original SIGTERM finding)
    - Threat-model T-23-05 (cleanup must not leak secrets) and T-23-07 (--pause-between-passes path validation)
  </read_first>
  <behavior>
    The phase scope says "migrations/apply.sh" but the repo currently has no top-level apply.sh — the actual apply work is inside `templates/.claude/scripts/migrate-NNNN-*.sh` engines. The trap MUST land where it actually matters:
    1. The trap goes into the migration-0019 engine (and 0017 for parity, since 0017 follows the same shape — see CONTEXT D-07 audit clause)
    2. The `--pause-between-passes <signal-file>` flag is ADDED to the migration-0019 engine (test-only, but lives in the engine itself per D-05)
    3. The test fixture in `migrations/run-tests.sh` orchestrates: spawn the engine in background → wait until signal-file is created by the engine before pass 2 → SIGTERM the engine → verify trap fired + no half-written canonical file + re-run succeeds

    Test cases (single new test, named `test-sigterm-mid-apply-preserves-state`):
    1. RED: create temp project fixture (mirror 0019 fixture 01-fresh-apply); run `migrate-0019-…sh --pause-between-passes /tmp/sigterm-test-XXXX &` in background; assert the signal file is created; SIGTERM the engine; assert (a) trap fires (engine exit code is 143 — SIGTERM — OR engine prints "trapped TERM, running cleanup"), (b) no `cron-monitor.ts` exists in any wrapper root (state preserved — pass 2 never wrote), (c) re-running the engine without --pause flag succeeds and produces the canonical post-state.
    2. T-23-05: cleanup output captured to file; assert `! grep -qE "(SENTRY_DSN|API_KEY|TOKEN)=" /tmp/cleanup-output.txt`.
    3. T-23-07: `migrate-0019-…sh --pause-between-passes /etc/passwd` exits 2 with "test-only flag with non-fixture path"; `migrate-0019-…sh --pause-between-passes "$TMPDIR/sig"` proceeds normally.
  </behavior>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "emit_refuse_artifacts", direction: "upstream"})` on the 0019 engine (the function nearest the trap insertion); record risk. Also gitnexus_impact on `run_all` in run-tests.sh.

    **RED commit** (`test(23): F3 SIGTERM mid-apply preserves state — RED`):
    1. Add test function `test_sigterm_mid_apply_preserves_state` to `migrations/run-tests.sh`, registered after the test from Task 1.3:
       - Set up a fixture project from `migrations/test-fixtures/0019/01-fresh-apply/setup.sh` (or equivalent) in a tmpdir.
       - Create a signal-file path: `SIG="$tmpdir/sigterm-test.signal"`
       - Launch engine: `bash templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh --templates-dir "$TEMPLATES" --project-dir "$tmpdir" --pause-between-passes "$SIG" 2>"$tmpdir/cleanup-output.txt" &`
       - Capture engine PID: `ENGINE_PID=$!`
       - Poll for signal-file creation up to 10s: `for i in {1..50}; do [ -f "$SIG" ] && break; sleep 0.2; done; [ -f "$SIG" ] || { echo "engine never reached pause"; kill -9 $ENGINE_PID; exit 1; }`
       - Send SIGTERM: `kill -TERM $ENGINE_PID`
       - Wait for engine to exit (with 5s timeout): `wait $ENGINE_PID; engine_exit=$?`
       - Assert: no `cron-monitor.ts` exists in any wrapper root in $tmpdir
       - Assert: cleanup-output.txt does NOT contain `SENTRY_DSN=` or `API_KEY=` or `TOKEN=` (T-23-05)
       - Re-run without --pause: `bash templates/.claude/scripts/migrate-0019-…sh --templates-dir "$TEMPLATES" --project-dir "$tmpdir"` ; assert exit 0; assert cron-monitor.ts NOW exists in all clean wrapper roots
       - T-23-07 sub-tests:
         - Verify `bash …sh --pause-between-passes /etc/passwd` exits 2 + stderr contains "test-only flag with non-fixture path"
         - Verify `bash …sh --pause-between-passes "$TMPDIR/somefile"` is accepted (doesn't error on the flag parsing)
    2. Run `bash migrations/run-tests.sh test-sigterm-mid-apply-preserves-state 2>&1 | tee /tmp/red-f3.txt`
    3. Assert: test fails because the engine has neither the trap nor the --pause flag yet.
    4. Commit test ONLY.

    **GREEN commit** (`feat(23): F3 SIGTERM trap + --pause-between-passes (test-only) in 0019 engine — GREEN`):
    1. Modify `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`:
       a. Add flag parsing for `--pause-between-passes <file>`:
          ```bash
          PAUSE_SIGFILE=""
          # in the while-getopts loop, add:
          --pause-between-passes)
            PAUSE_SIGFILE="$2"
            # T-23-07 path validation: signal file MUST live under $TMPDIR or migrations/test-fixtures/
            case "$PAUSE_SIGFILE" in
              "$TMPDIR"/*|/tmp/*|*/migrations/test-fixtures/*) : ;;
              *) echo "migrate-0019: --pause-between-passes is a test-only flag; signal-file path must be under \$TMPDIR or migrations/test-fixtures/ (got: $PAUSE_SIGFILE)" >&2; exit 2 ;;
            esac
            echo "migrate-0019: WARNING — --pause-between-passes is a test-only flag; do not use in production" >&2
            shift 2
            ;;
          ```
       b. Add an idempotent `cleanup` function near the top of the script (after logging helpers):
          ```bash
          cleanup_fired=0
          cleanup() {
            [ "$cleanup_fired" -eq 1 ] && return 0
            cleanup_fired=1
            # T-23-05: do NOT print env vars or partial canonical contents.
            warn "trapped signal — cleanup running (no partial state written; re-run engine without --pause to complete)."
            # Remove the pause signal file if we created one.
            [ -n "$PAUSE_SIGFILE" ] && [ -f "$PAUSE_SIGFILE" ] && rm -f "$PAUSE_SIGFILE"
          }
          trap 'cleanup' INT TERM EXIT
          ```
       c. At the boundary between pass 1 (classification / dirty detection) and pass 2 (apply_root loop — line ~592 in the existing file), insert:
          ```bash
          if [ -n "$PAUSE_SIGFILE" ]; then
            : > "$PAUSE_SIGFILE"  # create the signal file
            # Wait up to 30s for the file to be deleted by the test, OR for a signal to interrupt us.
            for i in $(seq 1 300); do
              [ ! -f "$PAUSE_SIGFILE" ] && break
              sleep 0.1
            done
          fi
          ```
    2. ALSO add the same trap to `migrations/run-tests.sh` (the test harness itself — T-23-05 / SECURITY.md S6). Insert near the top after the color-setup block:
       ```bash
       runtests_cleanup() {
         # idempotent harness-level cleanup
         :
       }
       trap 'runtests_cleanup' INT TERM EXIT
       ```
    3. Run the test: `bash migrations/run-tests.sh test-sigterm-mid-apply-preserves-state`. Assert pass.
    4. Run the full harness: `bash migrations/run-tests.sh`. Assert: no regressions in other tests (the trap is harmless on normal exit).
    5. Commit production files (migrate-0019 script + run-tests.sh).
  </action>
  <verify>
    <automated>
      bash migrations/run-tests.sh test-sigterm-mid-apply-preserves-state &&
      grep -q "trap 'cleanup' INT TERM EXIT" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "trap 'runtests_cleanup' INT TERM EXIT" migrations/run-tests.sh &&
      grep -q "PAUSE_SIGFILE" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "test-only flag" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
    </automated>
  </verify>
  <done>
    RED→GREEN. 0019 engine has INT/TERM/EXIT trap + --pause-between-passes test-only flag with path validation. run-tests.sh has its own trap. Test passes deterministically (no sleeps in the assertion path — signal-file rendezvous).
  </done>
  <acceptance_criteria>
    - `bash migrations/run-tests.sh test-sigterm-mid-apply-preserves-state` exits 0
    - `trap 'cleanup' INT TERM EXIT` present in migrate-0019 engine
    - `trap 'runtests_cleanup' INT TERM EXIT` present in run-tests.sh
    - --pause-between-passes flag rejects paths outside $TMPDIR / test-fixtures (T-23-07)
    - cleanup stderr contains no `SENTRY_DSN=` / `API_KEY=` / `TOKEN=` echoes (T-23-05)
    - Full harness `migrations/run-tests.sh` still passes (no regressions)
    - gitnexus_impact recorded for affected symbols
    - RED commit + GREEN commit pair in history
  </acceptance_criteria>
</task>

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 4 — D-07 default-flip (depends on Task 3.1 because both edit the   -->
<!-- 0019 engine; sequencing avoids merge conflicts in the same file)        -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto">
  <name>Task 4.1 (Wave 4, D-07 audit): Migration 0017 atomic-refuse audit (read-only)</name>
  <files>(no files modified; produces an audit note in commit body)</files>
  <read_first>
    - templates/.claude/scripts/migrate-0017-axiom-destination.sh (lines 352-425 — the all-clean-gate + emit_refuse_artifacts function)
    - .planning/phases/23-observability-followups/CONTEXT.md D-07 (Migration 0017 audit precedes the change to align both engines' refuse semantics)
  </read_first>
  <action>
    Per D-07's audit clause: verify that migration 0017's atomic-refuse semantics ALREADY default to zero-side-effect (no patches to clean roots on default refuse), with `--allow-partial` being the opt-in for emit-everywhere.

    Concretely:
    1. Read migrate-0017's `emit_refuse_artifacts` function and its caller in the all-clean-gate block.
    2. Verify: on the default-refuse path (ALLOW_PARTIAL=0), patches are NOT emitted to CLEAN_DIRS — only to DIRTY_DIRS.
    3. Verify: on the --allow-partial path (ALLOW_PARTIAL=1), patches are emitted to all roots OR clean roots are simply applied (mutually exclusive paths).
    4. If verification PASSES (0017 already correct): record verdict in the commit body and proceed to Task 4.2 (the 0019 fix to align).
    5. If verification FAILS (0017 also has the 0019 bug): expand Task 4.2 to also fix 0017 in the same shape, and add a fixture for 0017 to match.

    Write the audit verdict as a commit:
    `chore(23): D-07 audit — migration 0017 atomic-refuse semantics verified`
    Commit body: documents the verdict + cites the line numbers in migrate-0017 that demonstrate it.

    This task produces NO file changes if 0017 is already correct (empty commit with `--allow-empty` is acceptable).
  </action>
  <verify>
    <automated>
      grep -q "DEFAULT refuse path is atomic" templates/.claude/scripts/migrate-0017-axiom-destination.sh &&
      # Verify migration 0017 does NOT emit patches to clean roots on default refuse (read its code path):
      ! grep -A 5 "ALLOW_PARTIAL.*-eq 0" templates/.claude/scripts/migrate-0017-axiom-destination.sh | grep -q "emit_refuse_artifacts_for.*CLEAN"
    </automated>
  </verify>
  <done>Audit verdict recorded in commit body. If 0017 already conforms (expected case), no production-file changes; commit is documentation-only.</done>
  <acceptance_criteria>
    - Commit body contains "AUDIT VERDICT:" followed by either "0017 conforms" or "0017 needs same fix as 0019"
    - If "0017 conforms": Task 4.2 proceeds as scoped
    - If "0017 needs same fix": Task 4.2 scope expands to include 0017 (executor escalates to orchestrator before proceeding)
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 4.2 (Wave 4, D-07): Migration 0019 atomic-refuse default-flip + fixture 06 + fixture 07</name>
  <files>
    templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh,
    migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh,
    migrations/test-fixtures/0019/07-allow-partial-emits-patches/setup.sh,
    migrations/test-fixtures/0019/07-allow-partial-emits-patches/verify.sh,
    migrations/test-fixtures/0019/07-allow-partial-emits-patches/expected-exit
  </files>
  <read_first>
    - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh lines 540-590 (the function being modified; including the all-clean gate at 577-590)
    - migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh (existing fixture — its assertion shape flips per D-07)
    - migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/setup.sh (used by fixture 07 as its starting state)
    - migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/expected-exit (current expected exit code)
    - templates/.claude/scripts/migrate-0017-axiom-destination.sh §all-clean-gate (reference shape — 0019 aligns to match)
    - .planning/phases/23-observability-followups/CONTEXT.md D-07 (default flips to zero-side-effect; --allow-partial opt-in; precedence: flag > env, both must explicitly opt in)
    - Task 4.1's audit verdict (commit body)
  </read_first>
  <action>
    [BLOCKING] Run `gitnexus_impact({target: "emit_refuse_artifacts", direction: "upstream"})` on the 0019 engine; record risk.

    Per D-07: change the migrate-0019 engine's default refuse behaviour from "patches everywhere" to "patches only on the dirty root(s)". The --allow-partial flag (existing) AND a new `ALLOW_PARTIAL=true` env var entry-point both restore the emit-everywhere behaviour. Precedence per Claude's Discretion in CONTEXT: flag wins over env, both must explicitly opt in.

    **Step 1 — Modify the engine** (single commit `feat(23): D-07 0019 atomic-refuse default zero-side-effect + ALLOW_PARTIAL env opt-in`):

    Edit `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`:

    a. Add ALLOW_PARTIAL env-var reading near the flag-parsing block (line 37-57), with flag-wins-over-env precedence:
       ```bash
       # D-07: ALLOW_PARTIAL env var opt-in (the --allow-partial flag still wins).
       # Both must explicitly evaluate to "true" / "1" / "yes" to enable patches on clean roots.
       _env_allow_partial=0
       case "${ALLOW_PARTIAL:-}" in
         1|true|yes) _env_allow_partial=1 ;;
       esac
       # CLI flag is parsed in the while-getopts loop above; --allow-partial sets ALLOW_PARTIAL=1.
       # Apply env-var only if the flag did NOT already set it.
       if [ "$ALLOW_PARTIAL" -eq 0 ] && [ "$_env_allow_partial" -eq 1 ]; then
         ALLOW_PARTIAL=1
         info "ALLOW_PARTIAL env var detected — treating as --allow-partial."
       fi
       ```

    b. Modify `emit_refuse_artifacts` function (lines 542-574) to gate the clean-roots loop on ALLOW_PARTIAL:
       ```bash
       emit_refuse_artifacts() {
         local i
         warn "  hand-modified wrapper root(s) detected:"
         for i in "${!DIRTY_DIRS[@]}"; do
           local dir="${DIRTY_DIRS[$i]}" stack="${DIRTY_STACKS[$i]}"
           warn "    DIRTY: $dir  (stack: $stack)"
           emit_refuse_artifacts_for "$dir" "$stack" "DIRTY"
           # Per-fingerprint-file diff against baseline (excerpt, for the operator).
           local files; files=$(stack_fingerprint_files "$stack")
           local f src tmpl
           src=$(stack_template_dir "$stack")
           for f in $files; do
             tmpl="$src/$f"
             if [ -f "$tmpl" ] && [ -f "$dir/$f" ]; then
               warn "      diff $f (excerpt vs known v1.17.0 baseline):"
               diff -u "$tmpl" "$dir/$f" 2>/dev/null | head -10 | sed 's/^/        /' >&2
             fi
           done
           warn "      wrote recovery artefact: $dir/.observability-0019.patch"
           warn "      recover: (a) revert the wrapper drift; (b) re-run migrate-0019;"
           warn "               (c) optionally splice .observability-0019.patch manually."
         done

         # D-07: default refuse is zero-side-effect on clean roots. Only --allow-partial
         # (or ALLOW_PARTIAL=1 env) restores the v0.6.0 "patches everywhere" behaviour
         # so operators with manual recovery automation can still get the splice aids.
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
             info "  would-be-clean roots (patches NOT emitted — default atomic refuse; pass --allow-partial or set ALLOW_PARTIAL=1 to also emit patches for clean roots):"
             for i in "${!CLEAN_DIRS[@]}"; do
               info "    CLEAN: ${CLEAN_DIRS[$i]}  (stack: ${CLEAN_STACKS[$i]})"
             done
           fi
         fi
       }
       ```

    c. Update the script's exit-code documentation at the top (lines 34-38) to reflect that the default refuse is now zero-side-effect on clean roots.

    **Step 2 — Flip fixture 06's assertion** (same commit):

    Edit `migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh`:
    - Existing assertion (lines 31-38) requires patches on ALL three roots — flip to: patches ONLY on the DIRTY root; clean roots have NO patch file.
    - Assertion shape:
      ```bash
      # D-07 — DEFAULT refuse is zero-side-effect on clean roots. Only the dirty root receives a patch.
      test -f "$DIRTY/.observability-0019.patch" || { echo "patch not emitted for DIRTY root"; exit 1; }
      test -s "$DIRTY/.observability-0019.patch" || { echo "patch empty at DIRTY root"; exit 1; }
      for d in "$CLEAN_A" "$CLEAN_B"; do
        test ! -e "$d/.observability-0019.patch" || { echo "D-07 VIOLATION: patch emitted to clean root $d in DEFAULT refuse path"; exit 1; }
      done
      ```
    - The output-matching grep for clean-root paths can stay (the script still NAMES them in stderr, just doesn't write to them).

    **Step 3 — Create fixture 07** (same commit):

    Create `migrations/test-fixtures/0019/07-allow-partial-emits-patches/`:
    - `expected-exit`: contents `0\n` (--allow-partial returns 0 because it migrates the clean roots; the dirty root is skipped but logged)
    - `setup.sh`: source-and-extend fixture 06's setup so the starting state is identical (2 clean, 1 dirty)
    - `verify.sh`: assert (a) `bash migrate-0019-…sh --allow-partial …` exits 0 (or 2 if 0019 returns 2 even when applying clean roots — match the engine's actual exit-code semantics for --allow-partial; see line 37 of the engine "--allow-partial mode = clean roots applied, dirty skipped" — likely returns 0 with informational dirty-skipped output); (b) clean roots received cron-monitor.ts (migrated); (c) dirty root has NO cron-monitor.ts (skipped); (d) `.observability-0019.patch` is present at the DIRTY root and the CLEAN roots (--allow-partial re-enables emit-everywhere per D-07).

    Wire fixture 07 into the test harness: edit `migrations/run-tests.sh` `test_migration_0019` function to include fixture 07 in its per-fixture loop (per Task 3.1's read of the existing 0019 test driver).

    **Step 4** — Run the full migration test harness: `bash migrations/run-tests.sh`. Assert all tests including fixture 06 (flipped), fixture 07 (new), and the Task 3.1 sigterm test pass.

    Commit as a single semantic commit (engine + fixtures + harness wiring all describe one logical change).
  </action>
  <verify>
    <automated>
      bash migrations/run-tests.sh test_migration_0019 &&
      grep -q "D-07: default refuse is zero-side-effect" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "ALLOW_PARTIAL env var detected" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh &&
      grep -q "D-07 VIOLATION" migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh &&
      test -f migrations/test-fixtures/0019/07-allow-partial-emits-patches/verify.sh &&
      test -f migrations/test-fixtures/0019/07-allow-partial-emits-patches/setup.sh
    </automated>
  </verify>
  <done>
    0019 engine default refuse is zero-side-effect on clean roots; --allow-partial + ALLOW_PARTIAL=1 env both opt in to emit-everywhere; fixture 06 flipped; new fixture 07 covers --allow-partial path.
  </done>
  <acceptance_criteria>
    - Full 0019 fixture suite passes (fixtures 01-07)
    - Engine documentation reflects new default
    - Fixture 06 verify.sh asserts CLEAN roots have NO patch in default mode
    - Fixture 07 verify.sh asserts clean roots are migrated AND patched under --allow-partial
    - ALLOW_PARTIAL=1 env var also triggers opt-in (flag precedence preserved)
    - gitnexus_impact on emit_refuse_artifacts recorded
  </acceptance_criteria>
</task>

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 5 — Version bump + CHANGELOG + ADR + final verification            -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto">
  <name>Task 5.1 (Wave 5, ADR-0029): Author cron-monitor-sdk-composition ADR</name>
  <files>docs/decisions/0029-cron-monitor-sdk-composition.md</files>
  <read_first>
    - .planning/phases/23-observability-followups/CONTEXT.md §"Discussion log" OQ-8 (all 5 shapes A/B/C/D/F with rationales)
    - .planning/phases/23-observability-followups/DISCUSSION-LOG.md OQ-8 table (the alternatives table)
    - docs/decisions/0028-sentry-crons-healthz-conventions.md (template for ADR shape + tone)
    - docs/decisions/0027-postphase-observability-hook.md (another template — short ADRs)
    - Task 2.1's GREEN commit (the actual Shape A implementation — ADR's Consequences section references this)
  </read_first>
  <action>
    Author `docs/decisions/0029-cron-monitor-sdk-composition.md` capturing D-08 Shape A. Use Phase 22 ADR 0028 as the structural template.

    Required sections (per CONTEXT §"ADR candidate"):

    **# 0029 — cron-monitor SDK composition (Shape A)**
    Status: Accepted
    Date: 2026-05-29
    Phase: 23-observability-followups
    Supersedes: none (extends 0028's cron-monitor conventions)

    **## Context**
    Phase 22 reinvented Sentry's in_progress→ok/error lifecycle (duration tracking, thenable handling) around a 3-source slug-resolution wrapper. `Sentry.withMonitor<T>(slug, callback, monitorConfig?): T` ships in `@sentry/core` and is re-exported by `@sentry/cloudflare`. Post-PR-#53 the user requested a refactor to compose with the SDK helper rather than reinvent the lifecycle. Five honest shapes considered.

    **## Decision**
    Shape A — compose `Sentry.withMonitor` underneath our existing outer wrapper. Preserve `cron-monitor.ts:137-148` (fail-safe + slug resolution + monitorConfig build); replace `:148-181` (the lifecycle) with a single `await Sentry.withMonitor(monitorSlug, () => handler(controller, env, ctx), monitorConfig);` call.

    **## Alternatives Rejected**

    | Shape | Description | Why rejected |
    |-------|-------------|--------------|
    | B (Drop-in replacement) | `withCronMonitor(handler, config?) = (c, e, ctx) => Sentry.withMonitor(resolveSlug(...), () => handler(c, e, ctx), buildMonitorConfig(config))` | Drops R02 fail-safe (Sentry logs warning on no-DSN). Drops R04 swallow. Loses D6's silent-on-no-DSN behaviour. |
    | C (Deprecate + parallel `withCronMonitorV2`) | Keep v0.6.0 wrapper with `@deprecated`; add `withCronMonitorV2` as Shape A | +50 LOC per file. Zero downstream risk but compounds future maintenance — two wrappers to keep in sync for the deprecation window. |
    | D (Compose with SDK-throw firewall via stack inspection) | Shape A but wrap `Sentry.withMonitor` in additional try/catch that catches errors whose stack frame includes `captureCheckIn` and swallows them | Restores R02/R04 at significant complexity cost. Brittle stack-frame inspection. High test surface. |
    | F (No refactor — port only `duration` tracking pattern) | +8 LOC per file. All Phase 22 contracts preserved. | Loses strategic value of using upstream's primitive. User's "baked in" directive interpreted as a genuine refactor, not a touch-up. |

    **## Consequences**

    **Preserved contracts (Phase 22):** D6 (3-source slug resolution), R02 fail-safe no-DSN, D11 (multi-cron explicit-slug), D12 (monitorConfig 2nd-arg forwarding shape).

    **Documented regression:** R02/R04 SDK-error swallow drops. `Sentry.withMonitor` re-throws SDK transport errors during `captureCheckIn`. The outer `withObservabilityScheduled` wrapper catches these (verified in Task 2.1's commit body). Operators see SDK transport failures in their normal error-capture path instead of silent swallow. `SENTRY_DEBUG=1` is no longer the surfacing mechanism for SDK errors.

    **Documented addition:** `withIsolationScope` wrapping. Each cron run gets its own Sentry scope. Non-breaking; correctness improvement (scope tags / breadcrumbs / user-context no longer leak between cron invocations).

    **Downstream impact:** fxsa and callbot pull `add-observability 0.7.0` → see the regression + addition. CHANGELOG.md 0.7.0 calls both out explicitly. No code change required downstream.

    **Go stack unchanged.** `sentry-go` ships no `WithMonitor` equivalent (Context7-verified). The Go `WithCronMonitor` impl IS the cross-stack parity. See D-09 / `cron_monitor.go` package-doc note.

    **## Links**
    - CONTEXT: `.planning/phases/23-observability-followups/CONTEXT.md` §D-08
    - Discussion log: `.planning/phases/23-observability-followups/DISCUSSION-LOG.md` §OQ-8
    - Implementation: this phase's Task 2.1 / 2.2 / 2.3 GREEN commits
    - Phase 22 contracts: `.planning/phases/22-sentry-crons-healthz/PLAN.md` §R02 §R04, `…/CONTEXT.md` §D6 §D11 §D12
    - SDK reference: `@sentry/cloudflare` re-export of `@sentry/core` `withMonitor<T>` in `packages/core/src/exports.ts`
  </action>
  <verify>
    <automated>
      test -f docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "^# 0029" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "Shape A" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "Alternatives Rejected" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "withIsolationScope" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -q "R02/R04" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -E "\\| B \\(|Shape B" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -E "\\| C \\(|Shape C" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -E "\\| D \\(|Shape D" docs/decisions/0029-cron-monitor-sdk-composition.md &&
      grep -E "\\| F \\(|Shape F" docs/decisions/0029-cron-monitor-sdk-composition.md
    </automated>
  </verify>
  <done>ADR-0029 authored with all 4 rejected shapes documented + consequences + Sentry-SDK reference. Ready for `/gsd-review` to audit before execute.</done>
  <acceptance_criteria>
    - File exists at docs/decisions/0029-cron-monitor-sdk-composition.md
    - Headers: Context / Decision / Alternatives Rejected / Consequences / Links present
    - All 4 rejected shapes (B, C, D, F) appear with their rejection rationale
    - The documented R02/R04 regression and withIsolationScope addition are spelled out
    - Commit: `docs(23): ADR-0029 cron-monitor SDK composition (Shape A)`
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 5.2 (Wave 5, D-01 part 1): SKILL.md version bump 0.6.0 → 0.7.0</name>
  <files>add-observability/SKILL.md</files>
  <read_first>
    - add-observability/SKILL.md (line 3 currently `version: 0.6.0`)
    - .planning/phases/23-observability-followups/CONTEXT.md D-01 (0.6.0 → 0.7.0 minor)
  </read_first>
  <action>
    Edit `add-observability/SKILL.md` line 3:
    - FROM: `version: 0.6.0`
    - TO: `version: 0.7.0`

    No other field in the frontmatter changes. The `implements_spec: 0.3.2` stays — Phase 23 does not change the spec version.

    No `claude-workflow` version bump (per D-01 — engine fix + tests + doc only, per the `versioning-tracks-migrations` invariant).

    No new migration (per N2 in CONTEXT — forward-only template change).

    Commit: `chore(23): D-01 bump add-observability 0.6.0 → 0.7.0`. Commit body cites D-01 and the version-bump justification (F5's withIsolationScope + R02/R04 SDK-error regression are observable downstream behaviour → honest minor).
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
    - No other lines in the frontmatter changed (compare git diff)
    - No claude-workflow SKILL.md version touched
    - No new migration file created
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 5.3 (Wave 5, D-01 part 2): CHANGELOG.md 0.7.0 entry</name>
  <files>add-observability/CHANGELOG.md</files>
  <read_first>
    - add-observability/CHANGELOG.md (if exists; if not, create with conventional Keep-a-Changelog header)
    - add-observability/SKILL.md (post Task 5.2 — confirm version is 0.7.0)
    - .planning/phases/23-observability-followups/CONTEXT.md §"Resolved decisions" (the regression+addition that need to be called out)
    - Phase 22 PR #53 body shape (for tone parity — informal but precise)
  </read_first>
  <action>
    Create or modify `add-observability/CHANGELOG.md` with a new `## 0.7.0 — 2026-05-29` entry at the top.

    If the file does not exist, create it with header:
    ```markdown
    # add-observability — CHANGELOG

    All notable changes to the `add-observability` skill. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

    Versioning: this skill ships an independent SemVer track from `claude-workflow`. Minor bumps reflect observable downstream behaviour changes in scaffolded templates.

    ```

    The 0.7.0 entry MUST contain THREE explicit sections matching the phase's three operator-visible changes:

    ```markdown
    ## 0.7.0 — 2026-05-29

    Phase 23 follow-ups from Phase 22's deferred review-gate residuals + a user-directed `withCronMonitor` refactor. See `.planning/phases/23-observability-followups/CONTEXT.md` for the full decision basis and `docs/decisions/0029-cron-monitor-sdk-composition.md` for the architectural rationale.

    ### Added

    - **F2 — `/healthz` per-probe timeout** in all 4 stacks (TS Cloudflare Worker, TS Cloudflare Pages, TS Supabase Edge, Go fly-http). Default 2000ms (TS `DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS`, Go `defaultHealthzProbeTimeout`); caller overrides via the existing probe-registration shape (TS: 3rd arg to `healthzHandler`; Go: `HealthzDeps.ProbeTimeout`). Aborted probes report as `{status: "degraded", checks: {<probe>: "timeout"}}` — the string `"timeout"` distinguishes timeout from genuine probe failure.
    - **`Sentry.withMonitor` composition** in 3 TS stacks' `withCronMonitor` (worker, pages, supabase-edge) — see "Changed" below for the regression that comes with this.
    - **`withIsolationScope` wrapping per cron run** (via `Sentry.withMonitor`). Each cron invocation now runs in its own Sentry scope; tags, breadcrumbs, and user-context no longer leak between consecutive runs. Non-breaking; arguably a correctness improvement.
    - **`docs/decisions/0029-cron-monitor-sdk-composition.md`** ADR capturing D-08 Shape A reasoning with the 4 rejected shapes.

    ### Changed

    - **`withCronMonitor` (TS stacks) — Shape A refactor.** The in_progress / ok / error lifecycle (formerly `cron-monitor.ts:148-181`) is now composed via `Sentry.withMonitor(monitorSlug, () => handler(...), monitorConfig)`. The outer fail-safe + 3-source slug resolution + monitorConfig build (`cron-monitor.ts:137-148`) are preserved verbatim. Per-stack net LOC delta: ~−25 lines. Behavioural-parity test added (`cron-monitor.test.ts`).
    - **Migration 0019 atomic-refuse semantics flipped (D-07).** The default refuse path is now zero-side-effect on clean roots (matches migration 0017). Patches are written only to the dirty root(s). Operators who want the v0.6.0 "patches everywhere on refuse" behaviour for manual splice-aid pass `--allow-partial` (CLI) or `ALLOW_PARTIAL=1` (env). Flag wins over env when both are set; both must explicitly opt in.

    ### Regressed (documented)

    - **R02/R04 SDK-error swallow drops** in `withCronMonitor`. `Sentry.withMonitor` re-throws SDK transport errors during `captureCheckIn` instead of silently swallowing them. The errors now propagate to the outer `withObservabilityScheduled` capture path. **Operator action**: if your downstream observability layer (fxsa, callbot, etc.) treats cron-handler exceptions and SDK-transport exceptions identically, no change is needed. If you previously relied on the silent swallow to keep cron handlers running through Sentry outages, the new `withObservabilityScheduled` will surface those failures. Setting `SENTRY_DEBUG=1` no longer surfaces SDK-call failures from inside `withCronMonitor` — the SDK now surfaces them through normal error paths.

    ### Internal

    - **F1** — `add-observability/init/INIT.md` Phase 5 per-stack subsections (worker, pages, supabase-edge, go) gained ≤5-line `withCronMonitor` composition notes citing the per-stack composition order (D5a/D5b/D5d) with file:line links into the wrapper source.
    - **F3** — Migration test harness (`migrations/run-tests.sh`) and migration-0019 engine added `trap 'cleanup' INT TERM EXIT`. A test-only `--pause-between-passes <signal-file>` flag enables deterministic SIGTERM testing without timing-fragile sleeps.
    - **F4** — `migrations/run-tests.sh` added `test-skill-md-version-matches-latest-migration-to-version` — asserts `skill/SKILL.md` `version` equals the highest-numbered migration's `to_version`. Catches the drift bug that PR #52 introduced.
    - **D-09** — `add-observability/templates/go-fly-http/cron_monitor.go` package doc gained a ≤5-line note explaining that `sentry-go` ships no `WithMonitor` equivalent. The Go `WithCronMonitor` impl is the cross-stack parity for the missing helper.

    ### Operator migration notes

    Existing installs already have `v0.6.0`'s `cron-monitor.{ts,go}` and `healthz-snippet.{ts,go}` copied into their wrapper directories. There is NO migration auto-retrofit (forward-only template change per Phase 23 N2). Two paths:

    1. **Stay on v0.6.0 behaviour**: do nothing. Your installed wrappers keep working.
    2. **Adopt v0.7.0 behaviour**: re-copy the updated templates from `add-observability/templates/{stack}/cron-monitor.{ts,go}` and `healthz-snippet.{ts,go}` into your wrapper directories. The R02/R04 SDK-error regression applies once you adopt; verify your outer wrapper catches SDK-transport failures.
    ```

    Commit: `docs(23): D-01 CHANGELOG 0.7.0 entry — F2/F5/D-07/regression callout`.
  </action>
  <verify>
    <automated>
      grep -q "^## 0.7.0" add-observability/CHANGELOG.md &&
      grep -q "Shape A" add-observability/CHANGELOG.md &&
      grep -q "R02/R04 SDK-error swallow drops" add-observability/CHANGELOG.md &&
      grep -q "withIsolationScope" add-observability/CHANGELOG.md &&
      grep -q "DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS\\|2000ms\\|2 seconds" add-observability/CHANGELOG.md &&
      grep -q "ALLOW_PARTIAL\\|--allow-partial" add-observability/CHANGELOG.md &&
      grep -q "F1\\|INIT.md" add-observability/CHANGELOG.md &&
      grep -q "F3\\|SIGTERM\\|trap" add-observability/CHANGELOG.md &&
      grep -q "F4\\|test-skill-md-version-matches-latest-migration-to-version\\|drift" add-observability/CHANGELOG.md &&
      grep -q "D-09\\|sentry-go" add-observability/CHANGELOG.md
    </automated>
  </verify>
  <done>CHANGELOG.md has a 0.7.0 entry covering all 5 F-items + D-07 + D-09 with explicit Regressed (documented) section calling out R02/R04.</done>
  <acceptance_criteria>
    - 0.7.0 entry exists in add-observability/CHANGELOG.md
    - The three required callouts (F2, F5 + R02/R04 regression, D-07 default flip) all appear
    - withIsolationScope addition called out
    - Operator migration notes section explains the forward-only template change
    - F1, F3, F4, D-09 also covered in Internal section
  </acceptance_criteria>
</task>

<task type="auto">
  <name>Task 5.4 (Wave 5, final verification): Full test harness pass</name>
  <files>(no files modified; verification gate)</files>
  <read_first>
    - migrations/run-tests.sh (the harness)
    - add-observability/templates/run-template-tests.sh (if exists — the per-template harness)
    - .planning/phases/23-observability-followups/CONTEXT.md G6 (test count target: migration 178+2 → 180, template 228+3 → 231)
  </read_first>
  <action>
    Final pre-commit gate before /gsd-review. Run BOTH test harnesses end-to-end with no filter, capture output, and assert green:

    1. `bash migrations/run-tests.sh 2>&1 | tee /tmp/final-migration-tests.txt; echo "exit=$?"`
       - Assert exit 0
       - Assert PASS count ≥ 178 + 2 (Phase 22 baseline + F4 drift + F3 sigterm = at least 180). The F4 + F3 tests must appear in PASS log.

    2. `bash add-observability/templates/run-template-tests.sh all 2>&1 | tee /tmp/final-template-tests.txt; echo "exit=$?"`
       - Assert exit 0
       - Assert PASS count ≥ 228 baseline + behavioural-parity tests added by Tasks 2.1/2.2/2.3 + healthz-timeout tests added by Tasks 1.4/1.5/1.6/1.7.

    3. Run gitnexus_detect_changes per ./CLAUDE.md "MUST run gitnexus_detect_changes() before committing":
       - `gitnexus_detect_changes()` — verify changes only affect expected symbols and flows (the ones enumerated in <gitnexus_required_symbols>).
       - If unexpected symbols flagged: surface as CHECKPOINT, do not commit.

    4. Print phase-completion summary to stdout in this exact format:
       ```
       Phase 23 — observability-followups — FINAL VERIFICATION
       =======================================================
       Migration tests:   <PASS>/<TOTAL>  (was 178; now <TOTAL>)
       Template tests:    <PASS>/<TOTAL>  (was 228; now <TOTAL>)
       gitnexus changes:  <expected | unexpected>
       Files modified:    <count> across <stacks-changed>
       Decisions covered: D-01..D-09 (all 9 lock-state preserved)
       ADR-0029:          authored
       SKILL.md:          0.6.0 → 0.7.0
       CHANGELOG.md:      0.7.0 entry added
       ```

    Commit: `chore(23): final verification — all harnesses green; Phase 23 ready for /gsd-review`. May be `--allow-empty` if the verification produced no file changes.
  </action>
  <verify>
    <automated>
      bash migrations/run-tests.sh &&
      bash add-observability/templates/run-template-tests.sh all
    </automated>
  </verify>
  <done>Both test harnesses pass. gitnexus_detect_changes reports only expected symbols. Phase summary printed.</done>
  <acceptance_criteria>
    - migrations/run-tests.sh exits 0 with ≥ 180 passing tests
    - run-template-tests.sh all exits 0 with no regressions
    - gitnexus_detect_changes() reports only the symbols listed in <gitnexus_required_symbols>
    - Phase summary printed to stdout in the required format
  </acceptance_criteria>
</task>

</tasks>

<verification>
**Phase-level verification (run after Task 5.4):**

1. **Decision coverage** — every D-XX (D-01..D-09) has at least one task implementing it:
   - D-01 → Tasks 5.2 + 5.3
   - D-02 → entire batched plan (this PLAN.md is one phase, not split)
   - D-03 → Tasks 1.4 + 1.5 + 1.6 + 1.7
   - D-04 → Task 1.3 (uses grep + awk only)
   - D-05 → Task 3.1 (`--pause-between-passes` flag)
   - D-06 → Task 1.3 (test name + location)
   - D-07 → Tasks 4.1 + 4.2
   - D-08 → Tasks 2.1 + 2.2 + 2.3 (Shape A) + Task 5.1 (ADR-0029)
   - D-09 → Task 1.2

2. **Goal coverage** — every G1..G8 has evidence:
   - G1 → INIT.md 4 stack subsections (Task 1.1)
   - G2 → 4 healthz-snippet timeout impls + tests (Tasks 1.4-1.7)
   - G3 → trap + sigterm test (Task 3.1)
   - G4 → drift test (Task 1.3)
   - G5 → SKILL.md 0.7.0 bump only; no claude-workflow bump; no new migration (Tasks 5.2 + 5.3 + N2 compliance)
   - G6 → final harness pass (Task 5.4)
   - G7 → Shape A composition tests + impl (Tasks 2.1-2.3)
   - G8 → Go SDK gap doc note (Task 1.2)

3. **Threat-model coverage** — every T-23-NN has a mitigation owner task:
   - T-23-01 (I, withIsolationScope) → Tasks 2.1-2.3 (assertion in parity tests)
   - T-23-02 (D, SDK-error propagation) → Task 2.1 (middleware.ts verification recorded in commit body)
   - T-23-03 (I, healthz timing oracle) → Tasks 1.4-1.7 (2s timeout + "timeout" sentinel)
   - T-23-04 (D, leaked resources on abort) → Tasks 1.4-1.7 (Promise.race + ctx propagation)
   - T-23-05 (T, signal cleanup secret leak) → Task 3.1 (cleanup output assertion)
   - T-23-06 (E, --allow-partial misuse) → Task 5.3 (CHANGELOG operator-facing note) — ACCEPTED
   - T-23-07 (S, test-only flag in prod) → Task 3.1 (path validation in flag parser)

4. **Test count target (G6):**
   - migrations/run-tests.sh: 178 → 180 (+2: F4 drift, F3 sigterm)
   - add-observability/templates/run-template-tests.sh all: 228 → 231+ (+1 healthz timeout test × 4 stacks - 1 stack-overlap + 1 cron-monitor parity test × 3 stacks)

5. **gitnexus_impact ledger** — `<gitnexus_required_symbols>` table fully populated; every task that touches a named symbol has its `gitnexus_impact` risk level recorded in its commit body.
</verification>

<success_criteria>
- [ ] All 5 waves executed in order; tasks within waves 1 and 2 may parallelise
- [ ] Wave 1: F1 + D-09 + F4 + F2×4 stacks (7 commits minimum, 4 RED+GREEN pairs)
- [ ] Wave 2: F5×3 stacks (6 commits minimum, 3 RED+GREEN pairs)
- [ ] Wave 3: F3 (2 commits: RED + GREEN)
- [ ] Wave 4: D-07 audit (1 commit) + D-07 implementation (1 commit)
- [ ] Wave 5: ADR-0029 + SKILL.md + CHANGELOG.md + final verification (4 commits)
- [ ] Total commit count: 22-24 commits (depending on RED/GREEN pair count)
- [ ] add-observability/SKILL.md = `version: 0.7.0`
- [ ] add-observability/CHANGELOG.md has `## 0.7.0` entry covering all 5 F-items + D-07 + D-09 + R02/R04 regression
- [ ] docs/decisions/0029-cron-monitor-sdk-composition.md exists with all 4 rejected shapes
- [ ] No claude-workflow SKILL.md version touched
- [ ] No new migration file in migrations/
- [ ] migrations/run-tests.sh exits 0 with ≥ 180 tests
- [ ] add-observability/templates/run-template-tests.sh all exits 0
- [ ] gitnexus_detect_changes() reports only symbols in <gitnexus_required_symbols> table
- [ ] Threat-model dispositions documented in commits where mitigations land
- [ ] Branch `feat/observability-followups-v0.7.0` ready for `/gsd-review`
</success_criteria>

<output>
After completion:
1. Create `.planning/phases/23-observability-followups/SUMMARY.md` (the executor authors this from the GSD summary template at $HOME/.claude/get-shit-done/templates/summary.md)
2. Cut PR `feat: observability follow-ups + withCronMonitor Sentry.withMonitor composition (add-observability 0.7.0)` against `main` with PR body referencing CONTEXT.md + ADR-0029 + CHANGELOG.md 0.7.0 + the regression callout
3. Mandatory `/gsd-review` (multi-AI plan review) per Phase 22 ADR 0018 — F5 promotes this phase from "review-residual cleanup" to "architectural change touching downstream consumers"
4. Mandatory `/cso` per global CLAUDE.md — F5 changes how Sentry credentials/check-in payloads flow through `withIsolationScope` boundaries
5. `/qa` SKIPPED — no dev server in this repo (existing repo invariant)
</output>
</content>
</invoke>