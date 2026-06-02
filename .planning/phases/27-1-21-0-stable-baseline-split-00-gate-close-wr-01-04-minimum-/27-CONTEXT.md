# Phase 27: 1.21.0 stable baseline (SPLIT-00 gate) - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning
**Mode:** Decisions pre-locked via approved brainstorm (2026-06-02). This phase
had no open gray areas — discuss-phase ran in `--auto` to transcribe the
approved design into a downstream-consumable contract.

<domain>
## Phase Boundary

Ship **claude-workflow 1.21.0** as the cooled-off, stable baseline that the
downstream factiv repos (cparx, callbot, fx-signal-agent) upgrade to *before*
the three-repo split (SPLIT-01 / SPLIT-02) begins. This is the **workflow-side
gate** of `SPLIT-00-PREREQUISITES.md`.

**In scope:** WR-01..WR-04 (PR #60 deferred items), minimum-viable PROJECT.md,
STATE.md + ROADMAP.md drift refresh, split-prep groundwork (boundary audit of
`migrations/run-tests.sh` + annotations + ADR + SPLIT-01 correction — **no code
movement**), **migration 0022** (`to_version: 1.21.0`, re-syncs hardened
observability templates) + SKILL.md/CHANGELOG bump 1.20.0 → 1.21.0.

**Explicitly OUT of scope (do not start here):**
- The actual three-repo extraction (SPLIT-01 / SPLIT-02 — separate milestone).
- Moving/refactoring any framework code (split-prep is annotate + document only).
- Milestone v1.19.0 archive + new "repo-split" milestone — those are GSD
  lifecycle ops that run AFTER 1.21.0 merges (D-03).
- Downstream upgrades / 7-day cooling-off — tracked by SPLIT-00, not this phase.
- New product capabilities. (Per user decision A1, migration 0022 IS shipped to
  legitimize the 1.21.0 skill-version bump — see D-07. This reverses the original
  "no migration" framing.)

</domain>

<decisions>
## Implementation Decisions

### WR-01 — go-test counter double-count (run-template-tests.sh)
- **D-01:** Fix ONLY lines **633-634** in `add-observability/templates/run-template-tests.sh`:
  `PASSED=$(echo "$OUTPUT" | grep -c '^--- PASS' || echo "0")` and the FAILED
  twin. Root cause: `grep -c` **always prints a count (`0` on no match) AND
  exits 1 on no match**, so `|| echo "0"` appends a *second* `0`, yielding
  `"0\n0"`. Fix shape: drop the `|| echo "0"` (grep -c already emits `0`), e.g.
  `PASSED=$(echo "$OUTPUT" | grep -c '^--- PASS' || true)` — or capture then
  default. Preserve the existing pass/fail reporting behavior.
- **D-01a (firewall — DO NOT TOUCH):** Lines **128, 130, 558, 559** use
  `grep -oE … | grep -oE '^[0-9]+' || echo "0"`. These are **correct** —
  `grep -oE` prints *nothing* on no match, so `|| echo "0"` is the proper
  fallback. The planner/executor MUST NOT "fix" these; only the two `grep -c`
  lines are buggy. This distinction is a test in itself: a fix that changes
  128/130/558/559 is wrong.

### WR-02 — supabase-edge D-02a test state leak
- **D-02:** In `add-observability/templates/ts-supabase-edge/index.test.ts`, the
  `Deno.test("D-02a init() repeated-init determinism: …")` block (starts line
  209) restores `console.log` in its `finally` (line 231-233) but **never calls
  `_resetForTest()`** afterward — so `initialized=true` and the env-a singletons
  leak into subsequent tests in the same file. The test's own docstring (line
  206: `_resetForTest()  // cleanup`) documents the intended cleanup that the
  code omits. Fix: add `_resetForTest()` to the `finally` block (alongside
  restoring `console.log`) so BOTH console.log and singleton state are reset.
  ~2 lines. Use the EXISTING `_resetForTest(env)` helper (no new test seam —
  carries forward Phase 26 codex HIGH-3).

### WR-03 — direct buildSentryOptions unit tests × 3 stacks (TDD)
- **D-03:** Add direct unit tests for `buildSentryOptions(env)` across the three
  stacks that export it, RED→GREEN (`tdd="true"` — the helper already exists
  from Phase 26, so RED is "test file referencing the assertions that aren't yet
  covered"; if a stack's helper already satisfies an assertion the planner must
  still observe a meaningful RED, e.g. a deliberately-missing case, per TDD
  discipline). Target files:
  - cf-worker: `lib-observability.test.ts` (helper exported from `lib-observability.ts`)
  - cf-pages: `lib-observability.test.ts` (helper exported from `lib-observability.ts`)
  - openrouter-monitor: `src/observability/index.test.ts` (helper at `src/observability/index.ts:154`)
- **D-03a (CORRECTED per RESEARCH Blocker C):** `TRACE_SAMPLE_RATE` is a
  scaffold-time module **constant** (`const TRACE_SAMPLE_RATE = 0.1` /
  `{{TRACE_SAMPLE_RATE}}`), NOT a runtime env override — the helper has no
  env-parse behavior. Assertion set (5):
  1. `tracesSampleRate === TRACE_SAMPLE_RATE` (baked constant; 0.1 for openrouter)
  2. `environment === env.DEPLOY_ENV ?? "dev"` (test both set and unset)
  3. `release === env.SERVICE_NAME ?? SERVICE_DEFAULT` (test both set and unset)
  4. `sendDefaultPii === false`
  5. `dsn === env.SENTRY_DSN`
  Note: cf-worker/cf-pages helpers are token templates (`env.{{ENV_VAR_*}}`),
  testable only AFTER the harness materializes them; openrouter is directly
  testable. Confirm exact baked values during planning.
- **D-03b (decoupling firewall):** openrouter's existing `index.test.ts` D-02a
  block is deliberately decoupled from `buildSentryOptions` (Phase 26 codex
  MED-4). The new WR-03 tests are a SEPARATE `describe`/test block that directly
  exercises the helper — this does NOT violate MED-4 (which only forbids the
  *determinism proof* from depending on the helper). Keep the two concerns in
  separate blocks.

### WR-04 — openrouter entry uses buildSentryOptions
- **D-04:** Rewrite `add-observability/templates/openrouter-monitor/src/index.ts`
  to route Sentry options through the exported helper:
  `export default withSentry(env => buildSentryOptions(env), withObservabilityScheduled(withCronMonitor(checkCredit, {…})))`.
  Removes the hardcoded inline options object (currently `tracesSampleRate: 0.1`
  et al. at `src/index.ts:48-57`) so `TRACE_SAMPLE_RATE` actually reaches
  `withSentry` in the worked example — the whole point of DEF-1. This makes the
  worked example consistent with its own `env-additions.md` (which already
  documents this exact wiring) and with cf-worker/cf-pages.
- **D-04a (byte-symmetry re-verify):** The Phase 25 D-21 / Phase 26 SC-9
  byte-symmetry contract compares `cf-worker/lib-observability.ts` ↔
  `openrouter-monitor/src/observability/index.ts` (the OBSERVABILITY MODULE).
  WR-04 edits `src/index.ts` (the ENTRY file), which is NOT part of the symmetry
  pair, so symmetry should be unaffected. The plan MUST still re-run
  `diff -q add-observability/templates/ts-cloudflare-worker/lib-observability.ts add-observability/templates/openrouter-monitor/src/observability/index.ts`
  after the change and assert empty output (guard against accidental coupling).
- **D-04b (import):** `src/index.ts` must import `buildSentryOptions` from
  `./observability` (already a named export). Confirm the composition operator
  shape matches the existing `withObservabilityScheduled`/`withCronMonitor`
  signatures (entry currently wires them inline — preserve handler semantics).

### PROJECT.md — minimum-viable, forward-looking
- **D-05:** Create `.planning/PROJECT.md` capturing **product identity**, not a
  phase-by-phase retro. Sections: what claude-workflow is; core value
  (spec-first, migration-driven workflow scaffolder for AgenticApps projects);
  who uses it (AgenticApps repos incl. factiv downstreams); key constraints
  (migration-driven versioning per `versioning-tracks-migrations`; spec-first
  via GSD); current milestone; and the impending 3-repo split (point at
  SPLIT-00/01/02). Phases 01-26 history stays in `.planning/phases/` + git —
  PROJECT.md links there, it does not reconstruct it. Clears the STATE.md
  "PROJECT.md does not yet exist" pointer.

### Split-prep groundwork — audit + annotate ONLY (RETARGETED per RESEARCH Blocker B → user chose B1)
- **D-06 (RETARGETED):** `bin/gsd-tools.cjs` does NOT exist in this repo — it is the
  GSD *framework* (`~/.claude/get-shit-done/bin/`), a separate install, NOT
  claude-workflow's code. The repo's actual shared-able migration infra is
  **`migrations/run-tests.sh`** (~2500 lines: dispatcher + drift test +
  fixture-runner harness + inline fixtures). Audit `migrations/run-tests.sh`
  (and the migration framework files) and annotate each logical section/helper
  `# SHARED` or `# WORKFLOW`. **No code movement, no behavior change.**
  - `# SHARED` = migration-framework SPLIT-01 would extract: the dispatcher,
    `test_skill_md_version_matches_latest_migration_to_version` drift test, the
    fixture-runner harness, logging/pass-fail helpers, generic apply/verify utils.
  - `# WORKFLOW` = migration-content-specific logic that stays (per-migration
    setup/verify bodies tied to specific 00NN migrations, GSD-planning-specific checks).
  - Boundary test (from SPLIT-01): "if agenticapps-observability would need it to
    apply a migration → SHARED; if only useful for THIS repo's specific migrations
    or GSD planning → WORKFLOW."
- **D-06b (SPLIT-01 correction):** Add a note to `SPLIT-01-agenticapps-shared.md`
  correcting its premise: the extraction target is `migrations/run-tests.sh` +
  migration content, NOT `bin/gsd-tools.cjs` (which is the GSD framework, not this
  repo). The gsd-tools.cjs function list in SPLIT-01 (`phase-plan-index`,
  `state begin-phase`, etc.) belongs to the framework and is out of scope for the
  claude-workflow repo split.
- **D-06a:** Write ADR `docs/decisions/00NN-shared-extraction-boundaries.md`
  (next free ADR number — verify; 0034 is highest known) recording the
  shared/workflow boundary as the canonical reference SPLIT-01 Phase C executes
  against. Status: Accepted. Link SPLIT-00/01.

### Versioning (RESOLVED per RESEARCH Blocker A → user chose A1)
- **D-07 (A1 — ship migration 0022):** claude-workflow `1.20.0 → 1.21.0`, made
  legitimate by a NEW migration `migrations/0022-*.md` with `to_version: 1.21.0`.
  This lets `skill/SKILL.md version` bump to `1.21.0` while keeping the drift test
  GREEN (`test_skill_md_version_matches_latest_migration_to_version` compares
  SKILL.md to the HIGHEST migration's to_version — `migrations/run-tests.sh:2210`).
  Downstreams then pin by skill version `1.21.0` (SPLIT-00 gate works as written —
  no SPLIT-00 rewrite needed).
- **D-07a (migration 0022 payload — GROUNDED in 0021 mechanics):** Migration 0022 is
  a REAL "re-rev with dirty detection" migration mirroring `0021` (verified
  mechanism: `cp add-observability/templates/<stack>/<file> <wrapper>/<file>` with
  refuse-on-hand-modified via `.observability-0022.patch`). Consumer-facing payload:
  re-rev `lib-observability.ts` (cf-worker + cf-pages) + supabase-edge `index.ts`
  into consuming projects, delivering the Phase 26 **DEF-1** (`buildSentryOptions`
  helper) and **DEF-2** (REDACTED_KEYS auth-header redaction — a real security
  improvement) that Phase 26 D-04a deliberately kept OFF the migration chain.
  Migration 0022 corrects that: consumers at 1.20.0 do NOT have these in their
  wrapper; this delivers them. `from_version: 1.20.0`, `to_version: 1.21.0`,
  `type: re-rev-with-dirty-detection`, fixtures in `migrations/test-fixtures/0022/`.
  WR-01/02/03 stay claude-workflow-internal (not migrated). WR-04 (openrouter
  worked-example) is a scaffold, not consumer-migrated.
- **D-07a-COST (flagged for user):** This makes Phase 27 substantially larger than
  "WR bugfixes + docs" — a re-rev migration with dirty-detection + fixtures is
  ~Phase-25-sized work and reverses Phase 26 D-04a. This is the true cost of A1
  (vs A2 tag-only). Surfaced to user 2026-06-02 after research grounded the
  mechanism; user to confirm proceed-with-A1 vs downgrade-to-A2 before planning.
- **D-07b (SKILL.md + CHANGELOG):** Bump `skill/SKILL.md` `version: 1.20.0 → 1.21.0`.
  Promote BOTH Phase 26's `[Unreleased]` CHANGELOG entry AND Phase 27's changes
  into a new `## [1.21.0]` section in root `CHANGELOG.md`. No root `VERSION` file
  exists — SKILL.md is the version source of truth; do NOT create a VERSION file
  unless the planner finds the convention requires it.
- **D-07c:** add-observability stays **0.10.0** unless its own CHANGELOG/VERSION
  convention requires a patch — confirm during planning (its template fixes ship
  via migration 0022's re-sync, under claude-workflow's 1.21.0).

### STATE/ROADMAP drift refresh
- **D-08:** Refresh `.planning/STATE.md`: `status: executing` Phase 26 →
  reflect Phase 26 MERGED (PR #60, `46bb394`) + current position = Phase 27.
  Update milestone progress (now 3 phases). Refresh `.planning/ROADMAP.md`
  milestone header (the "v1.19.0 / migration" label shipped 1.20.0 — note the
  drift or correct the milestone framing) and mark Phase 26 Complete/merged.

### Claude's Discretion
- Exact bash idiom for the WR-01 fix (`|| true` vs capture-then-default).
- Exact PROJECT.md prose and section ordering (within D-05 constraints).
- ADR number selection (next free) and exact annotation comment wording.
- Whether WR-03 openrouter tests live in a new `buildSentryOptions.test.ts` or a
  new block inside `index.test.ts` (D-03b decoupling must hold either way).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Split plan (the gate this phase satisfies)
- `SPLIT-00-PREREQUISITES.md` — workflow-side gating checklist; 1.21.0 scope + cooling-off
- `SPLIT-01-agenticapps-shared.md` §"What lives here" + Phase C — the gsd-tools boundary this phase's ADR pre-decides
- `SPLIT-02-agenticapps-observability.md` — downstream consumer of the boundary (context only)

### WR items (exact locations)
- `add-observability/templates/run-template-tests.sh:633-634` — WR-01 bug (grep -c double-count); `:128,130,558,559` — DO-NOT-TOUCH firewall
- `add-observability/templates/ts-supabase-edge/index.test.ts:209-243` — WR-02 D-02a test missing `_resetForTest()` cleanup; helper at `index.ts:145` (`_resetForTest(env)`)
- `add-observability/templates/ts-cloudflare-worker/lib-observability.ts` + `.test.ts` — WR-03 cf-worker buildSentryOptions
- `add-observability/templates/ts-cloudflare-pages/lib-observability.ts` + `.test.ts` — WR-03 cf-pages buildSentryOptions
- `add-observability/templates/openrouter-monitor/src/observability/index.ts:154` (`buildSentryOptions`) + `index.test.ts` — WR-03 openrouter
- `add-observability/templates/openrouter-monitor/src/index.ts:30-60` — WR-04 entry rewrite
- `add-observability/templates/openrouter-monitor/env-additions.md` — documents the target WR-04 wiring pattern

### Contracts / prior decisions
- Byte-symmetry: Phase 25 D-21 + Phase 26 SC-9 — pair is `ts-cloudflare-worker/lib-observability.ts ↔ openrouter-monitor/src/observability/index.ts`
- `docs/decisions/0034-observability-init-singleton-invariant.md` — D-02a determinism contract (ADR-0034)
- `.planning/phases/26-worker-template-hardening/26-CONTEXT.md` — DEF-1/2/3 + WR provenance, codex HIGH-3 / MED-4 decoupling rules
- `.planning/phases/26-worker-template-hardening/SUMMARY.md` (if present) — WR-01..04 deferral source
- User rule `versioning-tracks-migrations` — engine/test fixes to existing migration get no version bump; no migration → no SKILL.md bump

### New artifacts this phase creates
- `.planning/PROJECT.md` (D-05)
- `docs/decisions/00NN-shared-extraction-boundaries.md` (D-06a)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_resetForTest(env)` — existing supabase-edge test seam (`index.ts:145`); WR-02 uses it, adds no new seam.
- `buildSentryOptions(env)` — already exported from cf-worker/cf-pages `lib-observability.ts` and openrouter `src/observability/index.ts:154` (Phase 26 DEF-1). WR-03 tests it directly; WR-04 wires the openrouter entry to it.
- Existing `*.test.ts` files per stack (vitest for cf-worker/cf-pages/openrouter; Deno.test for supabase-edge) — WR-03 extends these, no new harness.

### Established Patterns
- Migration drift test couples SKILL.md version to latest migration `to_version` — gates the no-SKILL-bump decision (D-07a).
- Byte-symmetry `diff -q` contract between cf-worker lib + openrouter observability module — WR-04 must not break it (D-04a).
- `// SHARED`/`// WORKFLOW` boundary mirrors SPLIT-01's "boundary test" — annotation only, extraction deferred.

### Integration Points
- `bin/gsd-tools.cjs` — the monolith whose exports get annotated (D-06); consumed by every gsd-* skill, so zero-behavior-change is mandatory.
- `add-observability/templates/run-template-tests.sh` — the harness; WR-01 fix affects only go-test reporting.
- Root `VERSION` + `CHANGELOG.md`; `skill/SKILL.md` version field (NOT bumped, D-07a).

</code_context>

<specifics>
## Specific Ideas

- WR-04 target wiring is verbatim from `openrouter-monitor/env-additions.md`:
  `export default withSentry(env => buildSentryOptions(env), withObservabilityScheduled(handler))`.
- 7-day cooling-off framing is WHY split-prep is annotate-only: any behavior
  change to gsd-tools would reset the SPLIT-00 cooling-off clock.

</specifics>

<deferred>
## Deferred Ideas

- **Actual gsd-tools extraction** → SPLIT-01 Phase C (next milestone).
- **Milestone v1.19.0 archive + new "repo-split" milestone** → after 1.21.0 merges (D-03).
- **`{{ENV_VAR_RELEASE}}` design** (CodeRabbit PR #60 follow-up) → future obs phase / SPLIT-02 Phase D.
- **`FIX-0017-ENGINE.md`** working-dir prompt → its own phase (migration 0017, separate scope).
- **Untracked session-noise triage** (`.claude/`, `AGENTS.md`, gstack `CLAUDE.md`, openrouter `package-lock.json`, stray `node_modules/`) → cleanup pass; decide commit vs .gitignore vs delete (not blocking 1.21.0).
- **Full ROADMAP/STATE retroactive bootstrap of Phases 01-24** → explicitly NOT done; D-05 minimum-viable PROJECT.md supersedes the need.

</deferred>

---

*Phase: 27-1-21-0-stable-baseline-split-00-gate*
*Context gathered: 2026-06-02*
