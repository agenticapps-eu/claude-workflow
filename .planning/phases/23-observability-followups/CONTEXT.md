# Phase 23 — Observability follow-ups (Phase 22 deferred items)

> **STATUS: RESOLVED — ready for `/gsd-plan-phase 23`.**
> All 9 open questions locked on 2026-05-29 via express-path discuss
> (see §"Resolved decisions" for D-01 through D-09 and
> §"Discussion log" for the per-question rationale + alternatives
> considered). Decisions are binding through plan + execute.

**Branch**: `feat/observability-followups-v0.7.0` (cut from `main@16e78ee`, 2026-05-29).
**Spec target**: `agenticapps-workflow-core@v0.4.0` — no spec change. All five items are §10.6/§10.7 host-discretion polish, test-suite hardening, or template-internal refactor.
**Version bump (locked per D-01)**: `add-observability 0.6.0 → 0.7.0` minor. F5's Shape A composition adds `withIsolationScope` wrapping + regresses R02/R04 SDK-error swallow → observable downstream behaviour → honest minor bump. F2 hitches along. No `claude-workflow` bump (engine fix + tests + doc only per *versioning-tracks-migrations* invariant). No migration.
**Date opened**: 2026-05-29
**Date resolved**: 2026-05-29
**Hand-off source**: Phase 22 (`feat/sentry-crons-healthz-v1.18.0`, PR #53) deferred-finding tables + post-merge `withMonitor` SDK helper observation (session-handoff.md:45).

<decisions>
## Resolved decisions (D-01 — D-09)

> **Source.** All decisions resolved via single-pass express-path discuss on
> 2026-05-29. The pre-discuss recommendations in §"Discussion log" (formerly
> §"Discussion gate") were locked verbatim after user confirmation that
> Shape A is the intended F5 refactor shape. See `23-DISCUSSION-LOG.md`
> for the full Q&A audit trail.

**D-01 — Version bump.** `add-observability 0.6.0 → 0.7.0` minor. No `claude-workflow` bump. No new migration. Forward-only template change for fresh installs; existing installs re-copy from updated template if they want F2 + F5 changes (runbook footnote suffices). *(OQ-1 resolution: option (c).)*

**D-02 — Batch all five items into one phase.** Counter to Phase 22 SECURITY.md's 22.1+22.2 split proposal. F1–F5 ship together on `feat/observability-followups-v0.7.0`. Per-item planning ceremony cost dwarfs per-item implementation cost; F5 sequences naturally after F2 (both touch `add-observability` templates, both ship in same minor bump). *(OQ-2 resolution: batch.)*

**D-03 — Healthz default probe timeout = 2 seconds, caller-configurable.** Per-stack constant: TS `DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000`, Go `defaultHealthzProbeTimeout = 2 * time.Second`. Caller overrides per-probe via the existing probe-registration shape. Aborted probes report as `{status: "degraded", checks: {<probeName>: "timeout"}}` — operator distinguishes timeout from genuine failure. *(OQ-3 resolution: 2s default + configurable.)*

**D-04 — F4 SKILL.md drift test uses minimal bash YAML parser, not `yq`.** `skill/SKILL.md` frontmatter is fixed-shape (`version: X.Y.Z` on its own line). One-line `grep ^version:` + one-line `awk` extracts the version. No new tool dependency. *(OQ-4 resolution: minimal parser. If a future phase needs richer YAML parsing, that's the trigger to revisit `yq` adoption.)*

**D-05 — F3 SIGTERM test uses a test-only `--pause-between-passes <signal-file>` engine flag.** Engine waits on the signal file before pass 2 when the flag is present. Test creates the file with the engine background-running, sends SIGTERM, asserts trap fires + no half-written canonical file + re-run succeeds cleanly. Deterministic, no timing-fragile sleeps. Flag is test-only — production-path code unchanged. *(OQ-5 resolution: option (b).)*

**D-06 — F4 drift test lives in `migrations/run-tests.sh`.** The test guards a migration-side invariant (every migration's `to_version` must match the shipped `skill/SKILL.md` version). Naming: `test-skill-md-version-matches-latest-migration-to-version`. Not in a new `tests/skill-drift.sh` despite the assertion touching `skill/` — the failure mode is "migration N declared `to_version` X but skill ships Y," which is a migration test. *(OQ-6 resolution: migration tests.)*

**D-07 — Migration engine atomic-refuse default flips to zero-side-effect; recovery patches require opt-in `--allow-partial` flag (or `ALLOW_PARTIAL=true` env).** Migrates R09's contracted behaviour from "patches everywhere on refuse" (current default) to "no patches by default, patches everywhere when `--allow-partial` is set." Restores "truly atomic refusal" as default. Migration 0017 audit precedes the change to align both engines' refuse semantics. Fixture 06's `verify.sh` assertion shape flips: clean roots no longer expected to receive patches in default-refuse path; new fixture exercises `--allow-partial` to assert the recovery-patches behaviour still works when opted in. *(OQ-7 resolution: option (b).)*

**D-08 — F5 refactor shape = Guarded Shape A (compose `Sentry.withMonitor` underneath the existing outer wrapper, with a pre-callback fall-back).** ★ **AMENDED 2026-05-29 post-multi-AI-review** — Codex review (`23-REVIEWS.md`) surfaced that the original Shape A formulation would skip cron execution when Sentry's `in_progress` check-in throws *before* the callback runs. The Guarded variant restores the "cron always runs" contract while preserving the SDK-composition strategy. Concrete change for each of the 3 TS files (`ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`): keep `cron-monitor.ts:137-148` (fail-safe + slug-resolution + monitorConfig build) intact; replace `:148-181` (in_progress/ok/error lifecycle) with:

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
  throw err; // handler-thrown errors propagate as before
}
```

Net per-file: ~−15 LOC (vs −25 for original Shape A) + behavioural-parity test +40 LOC (vs +30; adds one pre-callback-throw regression test per stack). **Preserved contracts:** D6 (3-source slug resolution), R02 (fail-safe no-DSN), D12 (monitorConfig 2nd-arg forwarding on in_progress only), **and now also the "cron always runs" guarantee** that original Shape A regressed. **Documented regression (narrowed):** R02/R04 SDK-error swallow drops *only for post-callback errors* — i.e., errors from the `ok`/`error` check-ins after the handler completed. Pre-callback errors no longer skip the cron; post-callback errors propagate to the outer wrapper. **Documented addition (newly characterized post-review):** `withIsolationScope` wrapping is NOT "purely non-breaking correctness improvement" — Codex correctly noted it can remove handler-set Sentry scope state (`Sentry.setTag`, breadcrumbs, etc. set inside the cron body) from the outer error-capture path after isolation unwinds. Downstream consumers relying on cron-body scope mutations becoming visible to outer error handlers will see different behaviour. This is documented in CHANGELOG 0.7.0 + ADR-0029 with the precise semantic. Go `WithCronMonitor` untouched (see D-09). *(OQ-8 resolution: Shape A; user confirmed 2026-05-29 via discuss-phase question. Post-review revision to Guarded Shape A confirmed 2026-05-29 via review-response question — see DISCUSSION-LOG.md §"Post-review revision — D-08 Guarded".)*

**D-09 — Go SDK gap is documented, not upstream-fixed.** A ≤5-line note added to `add-observability/templates/go-fly-http/cron_monitor.go` package doc explaining that `sentry-go` ships no `WithMonitor` equivalent and this impl IS the cross-stack parity for that helper. No GH issue against `getsentry/sentry-go`. No PR upstream. If a future maintainer wants to contribute upstream, the note links to this impl as reference. *(OQ-9 resolution: option (a) — document.)*

### Claude's Discretion

Within D-08 Shape A: precise placement of the `try` block around `Sentry.withMonitor`, the exact JSDoc wording for the documented regression, and the test-file naming for the behavioural-parity case are planner/executor discretion. Within D-07: the bash flag-vs-env-var precedence order is planner discretion (recommendation: flag wins over env var, both must explicitly opt in).

### Folded todos

None this phase. (No pending todos matched Phase 23 scope via `gsd-tools todo match-phase 23`.)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner, executor) MUST read these before planning or implementing.**

### Phase 22 contracts being preserved or revised by Phase 23
- `.planning/phases/22-sentry-crons-healthz/CONTEXT.md` — Phase 22 decision basis (D1, D5a, D6, D11, D12 referenced throughout Phase 23 decisions)
- `.planning/phases/22-sentry-crons-healthz/PLAN.md` §R02, §R04 — SDK-error swallow contract that D-08 Shape A regresses
- `.planning/phases/22-sentry-crons-healthz/REVIEW.md:129, :250` — F1 source (Stage 1 LOW, D5 location residual)
- `.planning/phases/22-sentry-crons-healthz/SECURITY.md:155-…` — F2 source (S4 MEDIUM healthz timeout)
- `.planning/phases/22-sentry-crons-healthz/SECURITY.md:255-…` — F3 source (S6 MEDIUM SIGTERM trap)
- `.planning/phases/22-sentry-crons-healthz/SECURITY.md:474-476` — Split proposal counter-argued by D-02
- `.planning/phases/22-sentry-crons-healthz/CONTEXT.md:84` — F4 source (N4 non-goal)
- `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:565-573` — R09 atomic-refuse behaviour revised by D-07

### Sentry SDK references (F5 / D-08 grounding)
- `@sentry/cloudflare` re-export of `@sentry/core` — `withMonitor<T>(slug, callback, monitorConfig?): T` signature (Context7-verified against `getsentry/sentry-javascript` `packages/core/src/exports.ts`)
- `@sentry/cloudflare` README → "Monitor Scheduled Tasks with Sentry Crons" — composition example used as reference for Shape A
- `sentry-go` API → `CaptureCheckIn(*CheckIn, *MonitorConfig) *EventID` only; no `WithMonitor` helper exists (Context7-verified against `getsentry/sentry-go`) — basis for D-09

### Current wrapper implementation (F5 refactor target)
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:133-183` — primary refactor target; canonical shape that ts-pages + ts-supabase-edge mirror
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts` — second refactor target
- `add-observability/templates/ts-supabase-edge/cron-monitor.ts` — third refactor target
- `add-observability/templates/go-fly-http/cron_monitor.go:1-32` — recipient of D-09 SDK-gap note (no behaviour change)

### Engine + drift-test targets (F3, F4)
- `migrations/run-tests.sh` — F3 SIGTERM test + F4 SKILL.md drift test land here
- `migrations/apply.sh` — F3 SIGTERM trap target (`trap 'cleanup' INT TERM EXIT`)
- `skill/SKILL.md` frontmatter — F4 drift-test parses this; `migrations/<latest>.md` `to_version` field is the comparison value

### Healthz snippet templates (F2)
- `add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts` — F2 timeout addition
- `add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts` — F2 timeout addition
- `add-observability/templates/ts-supabase-edge/healthz-snippet.ts` — F2 timeout addition
- `add-observability/templates/go-fly-http/healthz_snippet.go` — F2 timeout addition

### INIT.md sections (F1)
- `add-observability/init/INIT.md` Phase 5 subsections — F1 per-stack composition notes land in worker / pages / supabase-edge / go subsections; react-vite stays unchanged

### Project memory / repo invariants
- `~/.claude/projects/-Users-donald-Sourcecode-agenticapps-claude-workflow/memory/versioning-tracks-migrations.md` — engine bugfixes get no version bump (basis for D-01 no claude-workflow bump)
- `~/.claude/projects/-Users-donald-Sourcecode-agenticapps-claude-workflow/memory/prefers-judgment-over-asking.md` — express-path discuss authorisation
- `docs/decisions/0018-multi-ai-plan-review.md` — basis for non-skippable multi-AI plan review post-`/gsd-plan-phase 23` (F5 is architectural change)

### ADR candidate (to be authored in PLAN phase)
- `docs/decisions/0029-cron-monitor-sdk-composition.md` (new) — captures D-08 reasoning with the four rejected shapes

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- `@sentry/cloudflare`'s `withMonitor` (re-exported from `@sentry/core`) — directly composable per D-08 Shape A; no shim needed
- 3-source slug resolution (`resolveSlug` in each `cron-monitor.ts`) — preserved verbatim; nothing in `Sentry.withMonitor` precludes wrapping
- `buildMonitorConfig` helper — preserved verbatim; its output maps 1:1 to `Sentry.withMonitor`'s 3rd argument
- `debugLog` helper — kept; still useful for swallowed errors *outside* the `Sentry.withMonitor` call (e.g., if our `resolveSlug` ever throws)
- `migrations/run-tests.sh` test-driver harness — receives F3 + F4 cases without harness changes
- Existing `cron-monitor.test.ts` mocks for `@sentry/cloudflare` — extend with `withMonitor` mock for F5 behavioural-parity tests

### Established patterns
- Each TS template ships paired `.ts` + `.test.ts`; F5 must follow (one parity test per stack)
- Engine scripts in `migrations/` use POSIX bash with `set -euo pipefail`; F3 trap convention follows POSIX cleanup-on-signal idiom
- Frontmatter parsing across the repo is grep/awk-based (no `yq` dependency anywhere current) — D-04 aligns

### Integration points
- F5 changes are local to each `cron-monitor.ts` body; the function signature `withCronMonitor<E>(handler, config?)` stays — downstream callers (fxsa, callbot) need no signature changes
- F2 healthz-snippet timeout is opaque to caller — operators who already copied v0.6.0 keep working snippets; the timeout is forward-only
- F1 INIT.md edits land in static documentation — no executable code touched
- F3 + F4 tests run via existing `migrations/run-tests.sh all` harness; no CI wiring needed (repo has no CI yet — flagged as separate follow-up in handoff)

</code_context>

<specifics>
## Specific Ideas

- User explicitly invoked the refactor with the phrasing "withCronMonitor refactoring baked in" — interpreted as a genuine refactor (Shape A), not a cosmetic touch-up (Shape F). Shape A is what the user committed to.
- The behavioural-parity test (G7) is the firewall against fxsa/callbot regression when they pull the `0.7.0` minor — non-negotiable artifact.
- ADR-0029 (cron-monitor-sdk-composition) belongs in `docs/decisions/`. Authoring it in the PLAN phase rather than execute lets the multi-AI plan review (`/gsd-review`) audit the architectural rationale before any code lands.

</specifics>

<deferred>
## Deferred Ideas

Captured during Phase 23 scoping but explicitly out of scope:

- **Open a `getsentry/sentry-go` issue or PR proposing a `WithMonitor` helper** — D-09 documents the gap locally instead. Future phase if user wants upstream contribution.
- **Retrofit `Sentry.withMonitor` adoption back into Go via a thin AgenticApps shim** — only worth doing once `sentry-go` ships the helper upstream.
- **Add GitHub Actions CI** (`migrations/run-tests.sh` + `add-observability/templates/run-template-tests.sh all` on PR) — repo currently has zero CI gating. ~25 LOC of `.github/workflows/test.yml`. Flagged in session-handoff.md as Phase 24 candidate.
- **Multi-cron env-key support** (`SENTRY_CRON_MONITOR_SLUG_<HANDLER>_<CRON-EXPR>`) — explicitly deferred per Phase 22 D11.
- **Per-cron `monitorConfig` overrides for `schedule` / `maxRuntimeSeconds`** — Phase 22 D12 documents the metadata-only posture.
- **Client-side timeout enforcement on `withCronMonitor`** — deferred per Phase 22 D12; F2 is healthz-only.
- **Refactor Go `WithCronMonitor`** — N6; no `sentry-go` `WithMonitor` exists to compose against.

### Reviewed todos (not folded)

None — `gsd-tools todo match-phase 23` returned no matches.

</deferred>

## Background

Phase 22 shipped `withCronMonitor` + `/healthz` convention + migration 0019 in PR #53 with the explicit posture that four non-blocking items would be tracked as a follow-up phase. Three are review-gate residuals (1 Stage 1 LOW, 2 /cso MEDIUMs); one is a CONTEXT.md non-goal (N4) that the prior session deliberately scoped out to keep PR #53 single-purpose.

A fifth item (F5) was added during phase opening per direct user request: refactor the three TS `withCronMonitor` implementations to compose with Sentry's native `Sentry.withMonitor` helper (flagged in session-handoff as "possible Phase 24" / `withMonitor` SDK helper observation). Context7 lookup against `@getsentry/sentry-javascript@develop` confirms `withMonitor<T>(slug, callback, monitorConfig?): T` exists at `packages/core/src/exports.ts` and wraps callback in `withIsolationScope`. The same lookup against `getsentry/sentry-go` confirms the Go SDK ships no `WithMonitor` equivalent — Go's `WithCronMonitor` impl IS the missing helper, so F5 is **JS-only**. Refactor surface: 3 TS files (`ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`), not 4 stacks.

Each item is small in isolation. Phase 22's SECURITY.md suggested splitting the original four across a 22.1 + 22.2 sequence (`SECURITY.md:474-476`); F5 adds the only genuine architectural decision (refactor shape A/B/C/D/F — see OQ-8). The counter-proposal here is to batch all five into one phase because the per-item cost of splitting (two+ CONTEXT.md / PLAN.md / REVIEW.md sets) dwarfs the per-item implementation cost, and F5 sequencing-after-F2 is natural (F2 touches healthz template, F5 touches cron-monitor template; both ship in the same `add-observability` minor bump). **The split decision is OQ-2.**

## Source of each follow-up

| ID | Source ref | Severity at deferral | Why deferred from Phase 22 |
|----|-----------|----------------------|-----------------------------|
| F1 | `.planning/phases/22-sentry-crons-healthz/REVIEW.md:129, :250` (Stage 1 LOW, D5) | LOW | CONTEXT.md G1 promised per-stack composition in `add-observability/init/INIT.md` Phase 5 sections. Information landed in `cron-monitor.{ts,go}` source comments + runbook Part 3 instead. INIT.md itself unchanged. "Spirit honoured, artifact-location promise unmet." |
| F2 | `.planning/phases/22-sentry-crons-healthz/SECURITY.md:155-…` (S4, MEDIUM) | MEDIUM | `/healthz` snippet runs probes without per-probe timeout → a slow upstream becomes a timing oracle and the snippet blocks for as long as the slowest probe runs. Recommended pattern: `AbortSignal.timeout(2000)` per TS probe, `context.WithTimeout(2*time.Second)` per Go probe. |
| F3 | `.planning/phases/22-sentry-crons-healthz/SECURITY.md:255-…` (S6, MEDIUM) | MEDIUM | `migrations/run-tests.sh` / `apply.sh` engine has no `trap 'cleanup' INT TERM EXIT`. SIGTERM mid-apply on a 2-pass atomic migration would leave a partially-applied root. Engine is idempotent (re-running cleans up), but an explicit trap converts "recover by re-run" into "graceful interrupt with state preserved". |
| F4 | `.planning/phases/22-sentry-crons-healthz/CONTEXT.md:84` (N4, non-goal) | None at deferral — captured as PR-body follow-up | `migrations/run-tests.sh` does not currently assert `skill/SKILL.md version === latest migration to_version`. The drift bug fixed by Phase 22 commit 1 (PR #52 left SKILL.md at 1.16.0 while declaring migration `to_version: 1.17.0`) would have been caught at PR-time by such a test. Pure test-suite addition, no behaviour change. |
| F5 | `session-handoff.md:45` (post-merge observation, not in any formal review gate); current impl at `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:133-183`, `ts-cloudflare-pages/cron-monitor.ts`, `ts-supabase-edge/cron-monitor.ts` | None — discretionary refactor for internal SDK alignment | TS `withCronMonitor` reinvents the in_progress → ok/error lifecycle + duration tracking + async-aware thenable handling that `Sentry.withMonitor<T>` (sentry-javascript `packages/core/src/exports.ts`) already implements. Refactor shape decides whether we (a) preserve our 3-source slug resolution + SDK-error swallow + fail-safe no-DSN behaviour by composing `Sentry.withMonitor` underneath our outer wrapper, or (b) replace our impl wholesale and accept the semantic shifts (`withIsolationScope` wrapping, SDK-error propagation, no-DSN warning). Go stack stays as-is — `sentry-go` ships no `WithMonitor` equivalent. |

## Goals (must-haves, scaffolded — refine in discuss)

| # | Goal | Evidence shape (proposed) |
|---|------|----------------------------|
| G1 | INIT.md Phase 5 composition note added for each stack that ships `withCronMonitor` | `add-observability/init/INIT.md` diff against pre-phase HEAD shows per-stack Phase 5 subsections (worker / pages / supabase-edge / go) gain a ≤5-line paragraph citing `withCronMonitor` and the D5x composition rule with file:line link into `cron-monitor.{ts,go}`. react-vite section unchanged. |
| G2 | `/healthz` snippet ships per-probe timeout in all 4 stacks | `healthz-snippet.ts` × 3 wraps each probe in `AbortSignal.timeout(<TIMEOUT_MS>)` and treats abort as degraded; `healthz-snippet.go` wraps each probe in `context.WithTimeout(ctx, <TIMEOUT>)` with the same degraded-on-deadline behaviour. Per-stack test: degraded JSON returned within `<TIMEOUT_MS>+slack` ms when probe deliberately hangs. Default timeout value is OQ-3. |
| G3 | Migration engine traps SIGINT / SIGTERM and runs cleanup before re-raising | `migrations/run-tests.sh` adds `trap 'cleanup' INT TERM EXIT`. New `migrations/test-cases/sigterm-mid-apply.sh` (or equivalent): start a 2-pass migration in background, send SIGTERM after pass 1, assert (a) trap fires, (b) no half-written canonical file remains, (c) re-running the same migration succeeds cleanly. |
| G4 | SKILL.md drift guardrail test asserts `skill/SKILL.md` version matches latest migration `to_version` | New test case in `migrations/run-tests.sh` (precise location is a planner detail) parses `skill/SKILL.md` frontmatter and the highest-numbered file in `migrations/`; asserts equality. Self-test: temporarily desync them in a fixture branch → test fails with a clear "SKILL.md at vX.Y.Z but migration NNNN declares to_version: vA.B.C" message. |
| G5 | No version bump on claude-workflow; add-observability skill bumped iff F2 is classified as user-visible | If patch (`0.6.0 → 0.6.1`): `add-observability/SKILL.md` version bumped, CHANGELOG patch entry, **no new migration** (existing installs keep the v0.6.0 snippet they already copied). If no bump: F2 lands as a forward-only template change for future `init` runs. Resolution is OQ-1. |
| G6 | All existing 178 migration test cases + 228 template test cases stay green; F4's new guardrail makes 179 / unchanged 228; F3's new sigterm test makes 180; F5's behavioural-parity test bumps template suite to 229+ | Suite counts updated in PR body. |
| G7 | TS `withCronMonitor` composes with `Sentry.withMonitor` per OQ-8 resolution. Outer wrapper contract (3-source slug resolution, fail-safe no-DSN, monitorConfig forwarding shape) is preserved where Shape A/D wins; replaced verbatim where Shape B wins. Behavioural-parity test asserts the same in_progress + ok/error sequence + `monitorConfig` 2nd-arg semantics as v0.6.0. | 3 TS `cron-monitor.ts` files diff against pre-phase HEAD show the lifecycle code (lines 144-181 in worker) replaced by a `Sentry.withMonitor(slug, callback, monitorConfig)` call inside the existing fail-safe + slug-resolution scaffold (Shape A/D) or by a thin slug-resolving wrapper around `Sentry.withMonitor` (Shape B). New `cron-monitor.test.ts` cases: (i) emits `in_progress` checkin with monitorConfig, (ii) emits `ok` checkin without monitorConfig on success, (iii) emits `error` checkin without monitorConfig + rethrows on handler throw, (iv) handler runs unchanged when `SENTRY_DSN` unset (Shape A/D only — Shape B drops this assertion + adds an N6 documentation entry). |
| G8 | Go `WithCronMonitor` parity audit confirms no-op decision and documents the `sentry-go` SDK gap | A 3-line note added to `add-observability/templates/go-fly-http/cron_monitor.go` package doc explaining that `sentry-go` ships no `WithMonitor` equivalent and this impl IS the cross-stack parity for that helper. Optional: open a GH issue against `getsentry/sentry-go` proposing the helper (decided in OQ-9). |

## Decisions tentatively-locked (challenge in discuss)

**TD1 — Batch all four items into one phase.** Counter to SECURITY.md's 22.1+22.2 split proposal. Rationale: each item is <1 day of work; splitting doubles planning-artifact ceremony for no test-coverage or merge-risk gain. Held as a tentative; OQ-2 reopens it.

**TD2 — Default healthz probe timeout = 2 seconds.** Matches SECURITY.md S4's recommendation. Sentry Uptime probes typically time out at 5–10s, so 2s leaves ample margin for the JSON serialisation + Sentry-side network. Holding tentative pending OQ-3.

**TD3 — Healthz timeout uses `AbortSignal.timeout(ms)` (TS) and `context.WithTimeout` (Go).** Web-standard primitive on the TS side, stdlib on the Go side; no new dependency. Aborted probes report as `{status: "degraded", checks: {probeName: "timeout"}}` — operator can tell timeout from genuine failure.

**TD4 — Migration engine trap covers `INT`, `TERM`, `EXIT`.** `EXIT` is the catch-all; `INT` covers Ctrl-C; `TERM` covers `kill` / orchestration signals. Per *advanced-bash-scripting* / POSIX conventions for cleanup-on-signal.

**TD5 — SKILL.md drift test parses YAML frontmatter, not a regex.** Use `yq` if available, else a small Bash parser. Regex on YAML invites the same drift bug to slip through if frontmatter format changes. OQ-4 confirms `yq` dependency posture.

**TD6 — F1 (INIT.md Phase 5 notes) lands as a documentation-only commit, no test.** Doc commits in this repo's history don't get test coverage; adding a test for "INIT.md mentions withCronMonitor" would be brittle string-matching.

**TD7 — F5 lands as Shape A (compose `Sentry.withMonitor` underneath our outer wrapper).** Rationale: the 3-source slug resolution + fail-safe no-DSN + SDK-error swallow are *intentional* behaviours that PR #53's review gates explicitly validated (D6, R02, R04). Shape B (drop-in replacement) regresses three Phase 22 contracts. Shape A keeps our outer contract verbatim and replaces only the lifecycle innards (in_progress/ok/error sequencing + duration tracking + thenable handling) with the SDK call. Concretely: replace `cron-monitor.ts:144-181` with a single `try { await Sentry.withMonitor(monitorSlug, () => handler(controller, env, ctx), monitorConfig); } catch (e) { … }` block, keeping lines 137-143 (fail-safe) and the helper functions intact. Net LOC delta: ~−25 per file. Sentry's `withIsolationScope` wrapping becomes a behaviour *addition* (cleaner scope per cron run) — non-breaking for downstream. Held as tentative; OQ-8 confirms.

**TD8 — F5 behavioural-parity test is the gate-keeping artifact.** A new `cron-monitor.test.ts` case (one per stack) mocks `@sentry/cloudflare`'s `captureCheckIn` + `withMonitor` and asserts: (i) `withMonitor` called once with `(monitorSlug, callback, monitorConfig)`; (ii) `captureCheckIn` NOT called directly from our wrapper (must come from inside `withMonitor`); (iii) when `SENTRY_DSN` unset, neither is called and handler still runs; (iv) when handler throws, `withMonitor`'s rejection propagates and the outer fail-safe doesn't swallow it (Shape A explicitly re-throws). This test is the firewall against fxsa/callbot regression when they pull the new minor.

**TD9 — `add-observability` minor bump (`0.6.0 → 0.7.0`) for the combined F2 + F5 surface.** F2 alone is patch-shape; F5 alone is minor-shape (the `withIsolationScope` addition is a runtime behaviour change downstream consumers should opt into deliberately). Combining into one minor is honest semver: any downstream pulling the new template gets both. Migration not needed — same N2 reasoning (forward-only for fresh installs; existing installs re-copy if they want either change). Confirms OQ-1 recommendation toward (c).

## Discussion log — resolved 2026-05-29 (see §"Resolved decisions" above for the binding D-01–D-09)

> The OQs below are preserved verbatim as historical context: the alternatives
> considered for each decision, the pre-discuss recommendation, and the
> resolution. Downstream agents reading this section should not treat the
> "recommendation" lines as still-open — they were locked into D-01–D-09.

**OQ-1: Version bump shape.**
- (a) No bump anywhere — engine fix + test addition + doc patch + template-tweak, none individually requires user action.
- (b) `add-observability 0.6.0 → 0.6.1` patch only — honours the template-shape change in F2.
- (c) `add-observability 0.6.0 → 0.7.0` minor — F2 + F5 combined: F5's `withIsolationScope` addition (and possibly SDK-error propagation shift, depending on OQ-8 outcome) is observable downstream behaviour, which is honest minor-bump material; F2 hitches along.
- (d) `claude-workflow 1.18.0 → 1.18.1` patch — if any of F1/F3/F4 is reclassified as user-visible.

Recommendation pre-discuss (revised post-F5): **(c)** — F5 promotes the bump from patch to minor. Per TD9.

**OQ-2: Batch vs split.** Honour SECURITY.md's 22.1 + 22.2 proposal, or batch as Phase 23?
Recommendation pre-discuss: **batch**, per TD1.

**OQ-3: Healthz default probe timeout.** 2s (TD2 default) / 1s (more conservative) / 3s (more slack for slow upstreams) / make it caller-configurable with a sane default?
Recommendation pre-discuss: **caller-configurable, default 2s.** Constant gets named `DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000` in TS, `defaultHealthzProbeTimeout = 2 * time.Second` in Go; caller can override per-probe via the existing probe-registration shape.

**OQ-4: `yq` dependency for F4 frontmatter parsing.** Adopt `yq` (already common in this repo's tooling? — to verify) or write a 10-line Bash YAML parser inline?
Recommendation pre-discuss: **verify `yq` presence; if absent, write minimal parser** — the SKILL.md frontmatter is fixed-shape (`version: X.Y.Z` on its own line), so a 1-line `grep ^version:` plus a 1-line `awk` is sufficient and avoids a new tool dep.

**OQ-5: SIGTERM test mechanics for F3.** How does the test reliably reach the inter-pass window without timing-fragile sleeps? Options:
- (a) Inject a "pause here" hook the test can release.
- (b) Add a `--pause-between-passes <signal-file>` flag to the engine that waits on a file before pass 2.
- (c) Race with a short sleep and accept ~5% flake.
Recommendation pre-discuss: **(b)** — test-only flag, no production code path, deterministic.

**OQ-6: Does F4's drift test belong in `migrations/run-tests.sh` or in a new `tests/skill-drift.sh`?** The handoff said `migrations/run-tests.sh` but the assertion is about `skill/`, not migrations.
Recommendation pre-discuss: **`migrations/run-tests.sh`** — the test guards the migration-side invariant (every migration's `to_version` must match the shipped SKILL.md), so it belongs with migration tests. Naming inside that script: `test-skill-md-version-matches-latest-migration-to-version`.

**OQ-7: Atomic-refuse side-effects on clean roots (`--allow-partial` flag?).** Folded from CodeRabbit review of PR #53 (`templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:565-573`, classified Minor). R09's contracted behaviour on all-clean-gate refusal (engine exit 2) is to emit `.observability-0019.patch` and append to `.gitignore` in **every** wrapper root — including the would-be-clean siblings — so the operator can splice manually after fixing the offending dirty root. Fixture 06's `verify.sh` explicitly asserts this (`test -f "$d/.observability-0019.patch"` for `CLEAN_A`, `CLEAN_B`, `DIRTY`). CodeRabbit correctly observed that this technically mutates clean roots even though no new wrapper files are written. The trade-off is real:
- (a) Status quo (R09): patches everywhere on refuse — fast manual recovery, surprise git diff on clean roots.
- (b) Add `--allow-partial` flag (or `ALLOW_PARTIAL=true` env): default to zero-side-effect refuse, opt-in for the splice-aid patches.
- (c) Always zero-side-effect refuse on clean roots; emit patches only for the dirty root that triggered the refusal.
Recommendation pre-discuss: **(b)** — preserves R09 as opt-in for operators who want the recovery aid; restores "truly atomic refusal" as the default. Migrating 0019 to (b) is non-trivial because fixture 06 (and migration 0017's mirror behaviour, if it follows the same pattern) would need to flip its assertion shape; would need migration 0017 audit first to keep behaviour aligned between the two engines.

**OQ-8: F5 refactor shape.** Five honest shapes, picked from the Context7-confirmed `withMonitor<T>(slug, callback, monitorConfig?): T` signature in `@sentry/cloudflare`'s re-export of `@sentry/core`:
- (A) **Compose underneath outer wrapper.** Keep `cron-monitor.ts:137-148` (fail-safe + slug + monitorConfig build); replace `:148-181` (the in_progress/ok/error lifecycle) with `await Sentry.withMonitor(monitorSlug, () => handler(controller, env, ctx), monitorConfig)`. Preserves D6 slug resolution, R02 fail-safe, monitorConfig forwarding. **Loses R02/R04 SDK-error swallow** — `Sentry.withMonitor` re-throws everything. *Net behaviour change:* SDK transport errors during `captureCheckIn` now propagate to the outer `withObservabilityScheduled` instead of being silently swallowed.
- (B) **Drop-in replacement.** `withCronMonitor(handler, config?) = (controller, env, ctx) => Sentry.withMonitor(resolveSlug(config, env, controller), () => handler(controller, env, ctx), buildMonitorConfig(config))`. Smallest LOC. Drops R02 fail-safe (Sentry logs a warning when no DSN). Drops R04 swallow. Adds `withIsolationScope` wrapping by default.
- (C) **Deprecate + parallel export.** Keep `withCronMonitor` as-is with `@deprecated` JSDoc; add `withCronMonitorV2` as Shape A. Downstream picks per readiness. +50 LOC per file. Zero risk for fxsa/callbot in-flight adoption. Sunsets in a future major.
- (D) **Compose with explicit SDK-throw firewall.** Shape A but wrap `Sentry.withMonitor` in an additional try/catch that catches only errors *whose stack frame includes `captureCheckIn`* and swallows those, letting handler throws through. Requires brittle stack-inspection; high test surface. Restores R02/R04 but at significant complexity cost.
- (F) **No refactor.** Port only the `duration` tracking pattern (`timestampInSeconds()` diff) into our existing impl. ~+8 LOC per file. Zero composition with SDK helper. Clean but loses the strategic value of using upstream's primitive.

Recommendation pre-discuss: **(A)**. Per TD7: Shape A keeps three of four Phase 22 contracts (D6, R02 partial, D12) and trades the fourth (R02/R04 full SDK-error swallow) for upstream alignment + `withIsolationScope` benefit + duration accuracy. The R02/R04 regression is documentable as a known semantic shift; in practice SDK transport errors during `captureCheckIn` are exceptional and surfacing them to the outer wrapper (which still has its own try/catch from `withObservabilityScheduled`) is arguably more correct than silent swallow. **Strong second:** Shape F if the user prefers absolute zero behaviour change for in-flight downstream (fxsa, callbot) pulling 0.7.0 — but this loses the strategic value of the refactor.

**OQ-9: Go SDK gap follow-up.** Confirmed via Context7 that `sentry-go` ships no `WithMonitor` helper. Three options:
- (a) Document the gap in `cron_monitor.go` package doc (G8); take no upstream action.
- (b) Open a GH issue against `getsentry/sentry-go` proposing the helper with a link to our impl as a reference.
- (c) Send a PR to `sentry-go` implementing `WithMonitor` based on our `WithCronMonitor` (minus the slug-resolution + fail-safe + debug-log which are AgenticApps-specific).
Recommendation pre-discuss: **(a)** — documenting the gap is sufficient; (b) and (c) are nice-to-haves that compound Phase 23 scope without protecting any downstream contract.

## Out-of-scope (explicit non-goals)

- N1 — No spec change. v0.4.0 stays.
- N2 — No new migration. F2's template tweak is forward-only for fresh installs; existing installs already have v0.6.0's `healthz-snippet.{ts,go}` copied, and there is no auto-retrofit. Operators who want the timeout on already-installed snippets re-copy from the new template — runbook footnote suffices.
- N3 — No multi-cron env-key support (`SENTRY_CRON_MONITOR_SLUG_<HANDLER>_<CRON-EXPR>`) — explicitly deferred to a future minor per Phase 22 D11.
- N4 — No per-cron `monitorConfig` overrides for `schedule` / `maxRuntimeSeconds` — Phase 22 D12 already documents the metadata-only posture.
- N5 — No client-side timeout enforcement on `withCronMonitor` (deferred per Phase 22 D12; F2 is about `/healthz` only).
- N6 — No refactor of Go `WithCronMonitor`. `sentry-go` ships no `WithMonitor` equivalent (Context7 confirmed against `getsentry/sentry-go`). G8 documents the gap; OQ-9 decides upstream action posture.
- N7 — No expansion of slug resolution (the existing 3-source `explicit > env > auto-derive` ladder is preserved verbatim under Shape A; no new sources added). D11's multi-cron explicit-slug requirement stays.
- N8 — No removal of `monitorConfig` 2nd-arg semantics (the in_progress-only forwarding shape from D12 carries through `Sentry.withMonitor`'s 3rd parameter unchanged).

## Next steps

1. Resolve OQ-1 through OQ-9 via `/gsd-discuss-phase 23` (or inline confirmation if the user prefers).
2. `superpowers:brainstorming` against OQ-8 specifically before discuss — Shape A/B/C/D/F deserve a written alternatives table in RESEARCH.md, not just the inline summary above.
3. `/gsd-plan-phase 23` produces PLAN.md from this CONTEXT + the resolved discussion.
4. **`/gsd-review` (multi-AI plan review) is required pre-execution** — F5 promotes this phase from "review-residual cleanup" to "architectural change touching downstream consumers" (fxsa, callbot pull this code via `add-observability` minor bump). ADR-0018 makes the multi-AI review non-skippable for this shape.
5. Branch cut + execution. Revised expected scope: ~200 LOC across 4 stacks (F2: 4 stacks × +5 LOC = 20; F3: ~30; F4: ~15; F5: 3 TS files × −25 LOC net = −75 + behavioural-parity tests +90 ≈ +15; F1: ~50; doc patches: ~20). Net wrapper LOC actually *decreases* under Shape A; test LOC grows.
6. Stage 1 + Stage 2 + `/cso` (revised: **`/cso` is now required** — F5 changes how Sentry credentials/check-in payloads flow through `withIsolationScope` boundaries; trips the "touches API surface" criterion per global CLAUDE.md). `/qa` skipped (no dev server in this repo).

## ADR candidate

F5's refactor shape (whichever wins OQ-8) deserves `docs/decisions/0029-cron-monitor-sdk-composition.md`:
- **Context**: Phase 22 reinvented Sentry's in_progress→ok/error lifecycle around our 3-source slug resolution; `Sentry.withMonitor` ships in `@sentry/core` and offers a composable primitive.
- **Decision**: [resolved at OQ-8].
- **Alternatives rejected**: the four shapes that did NOT win, with the specific contract each one regressed.
- **Consequences**: how fxsa/callbot adoption notes change for the 0.7.0 minor; what the behavioural-parity test guards against; whether OQ-9 (Go SDK upstream issue/PR) is opened.

## Lineage

This phase exists because Phase 22 honored the "single-PR shape" the user requested and deliberately deferred non-blocking review-gate residuals rather than expanding scope mid-flight. Three of the four items came from formal review gates (Stage 1 LOW + 2 `/cso` MEDIUMs); one (F4) came from a CONTEXT.md non-goal flagged before the work started. Phase 22's `SUMMARY.md` and the session-handoff both enumerate them as "22.1 follow-ups (deferred from review gates, non-blocking)".
