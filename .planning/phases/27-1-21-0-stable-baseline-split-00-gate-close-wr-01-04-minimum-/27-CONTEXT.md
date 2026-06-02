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
STATE.md + ROADMAP.md drift refresh, split-prep groundwork (gsd-tools boundary
audit + annotations + ADR — **no code movement**), version bump 1.20.0 → 1.21.0.

**Explicitly OUT of scope (do not start here):**
- The actual three-repo extraction (SPLIT-01 / SPLIT-02 — separate milestone).
- Moving any code out of `bin/gsd-tools.cjs` (only annotate + document the boundary).
- Milestone v1.19.0 archive + new "repo-split" milestone — those are GSD
  lifecycle ops that run AFTER 1.21.0 merges (D-03).
- Downstream upgrades / 7-day cooling-off — tracked by SPLIT-00, not this phase.
- New capabilities or migrations. NO new migration ships (keeps the migration
  drift test green and avoids a SKILL.md version bump).

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
- **D-03a:** ~4 assertions each: (1) default `tracesSampleRate` when
  `TRACE_SAMPLE_RATE` unset; (2) `TRACE_SAMPLE_RATE` override is parsed and
  applied; (3) `environment` + `release` env-derivation (DEPLOY_ENV / SERVICE_NAME
  defaults); (4) `sendDefaultPii: false`. Confirm exact default values against
  each stack's helper during planning.
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

### Split-prep groundwork — audit + annotate ONLY
- **D-06:** Audit every export in `bin/gsd-tools.cjs` and annotate each with an
  inline `// SHARED` or `// WORKFLOW` marker. **No code movement, no behavior
  change** — preserves the stable cooling-off baseline.
  - `// SHARED` = migration-framework, anything SPLIT-01 Phase C extraction
    would need: `verify schema-drift`, `verify key-links`, the drift test,
    migration apply pipeline, fixture-runner helpers, logging/pass-fail utils.
  - `// WORKFLOW` = GSD-specific, stays in claude-workflow: `phase-plan-index`,
    `state begin-phase`, `phase complete`, `roadmap update-plan-progress`,
    `init phase-op`, `init execute-phase`, `agent-skills`, the GSD `commit` wrapper.
  - Boundary test (from SPLIT-01): "if agenticapps-observability would need to
    call it to apply a migration → SHARED; if only useful for managing GSD
    planning artifacts → WORKFLOW."
- **D-06a:** Write ADR `docs/decisions/00NN-shared-extraction-boundaries.md`
  (next free ADR number — verify; 0034 is highest known) recording the
  shared/workflow boundary as the canonical reference SPLIT-01 Phase C executes
  against. Status: Accepted. Link SPLIT-00/01.

### Versioning
- **D-07:** claude-workflow `1.20.0 → 1.21.0` (minor — additive test coverage,
  docs, engine-adjacent groundwork; no breaking change). Update `VERSION` +
  root CHANGELOG.
- **D-07a:** **NO new migration.** The migration drift test
  (`test-skill-md-version-matches-latest-migration-to-version`) enforces
  `skill/SKILL.md.version == latest migration to_version`. Phase 27 ships no
  migration → **NO SKILL.md version bump** (per `versioning-tracks-migrations`
  user rule). Phase 26's `[Unreleased]` CHANGELOG entry promotes to the 1.21.0
  section as part of this ship (verify during planning).
- **D-07b:** add-observability stays **0.10.0** — WR-01..04 are bugfixes to the
  existing 0.10.0 templates, not new features. **Confirm during planning**
  whether add-observability warrants a 0.10.1 patch bump or rides under
  claude-workflow's version only; default = no add-observability bump unless its
  own CHANGELOG/VERSION convention requires one.

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
