# ADR-0035 — Shared extraction boundaries for SPLIT-01 (agenticapps-shared)

**Status:** Accepted
**Date:** 2026-06-02
**Phase:** 27 — 1.21.0 stable baseline (split-prep groundwork, plan 04)
**Supersedes:** none
**Superseded by:** none

## Context

Three repos are planned to replace `claude-workflow` in a future milestone:

| Repo | Purpose |
|------|---------|
| `agenticapps-eu/claude-workflow` (slimmed) | Agentic discipline: GSD commands, planning skills, non-observability migrations |
| `agenticapps-eu/agenticapps-shared` (NEW) | Migration runner, drift test, common helpers shared by both other repos |
| `agenticapps-eu/agenticapps-observability` (NEW) | Observability scaffolder; pluggable destination adapters |

`SPLIT-01-agenticapps-shared.md` describes the extraction of the shared
infrastructure layer. `SPLIT-00-PREREQUISITES.md` gates the split on
claude-workflow 1.21.0 being stable on main for ≥7 days with all downstream
factiv repos upgraded.

### Blocker B correction: the real shared artifact is `migrations/run-tests.sh`

`SPLIT-01-agenticapps-shared.md` (Phase C) originally named
`bin/gsd-tools.cjs` as the primary file to audit and split. This was
incorrect: **`bin/gsd-tools.cjs` does not exist in this repo.** It is part
of the GSD framework, installed separately at `~/.claude/get-shit-done/bin/`.
The GSD framework is not claude-workflow's code; it is an independent tool
that claude-workflow consumes.

The actual shared-able migration infrastructure in this repo is
**`migrations/run-tests.sh`** (~2500+ lines): it contains the dispatcher,
the SKILL.md drift test, the fixture-runner harness, logging/pass-fail
helpers, and all per-migration test bodies. This ADR defines the
shared/workflow boundary for that file.

The gsd-tools function list in SPLIT-01 (`phase-plan-index`, `state
begin-phase`, `init phase-op`, etc.) belongs to the GSD framework, which is
out of scope for the claude-workflow repo split.

### Why pre-decide the boundary now (Phase 27)

Phase 27 is annotate-only — no code movement. The 7-day cooling-off baseline
must remain stable (any behavior change resets the SPLIT-00 clock). The
purpose of Phase 27's annotation pass is to pre-decide the boundary so that
when SPLIT-01 Phase C executes, the extraction is mechanical: look at each
`# SHARED` / `# WORKFLOW` annotation in `migrations/run-tests.sh` and act
accordingly.

## Decision

### Boundary test

> **If `agenticapps-observability` would need it to apply its own migrations
> → SHARED. If it is only useful for THIS repo's specific migrations or for
> GSD planning artifacts → WORKFLOW.**

### SHARED set — extracted to `agenticapps-shared`

These elements of `migrations/run-tests.sh` are generic framework machinery
reusable by any repo that follows the same migration discipline:

| Element | Rationale |
|---------|-----------|
| `_runtests_do_cleanup()` | Generic signal-trap harness lifecycle (INT→130, TERM→143); any migration runner needs this |
| `extract_to()` | Generic git-ref extraction utility; repo-agnostic fixture setup |
| `run_check()` | Generic pass/fail check runner; repo-agnostic harness primitive |
| `assert_check()` | Generic assertion helper with PASS/FAIL counter; repo-agnostic |
| `test_preflight_verify_paths()` | Generic verify-path auditor; walks migration frontmatter and checks `requires[*].verify` paths — any consumer repo with migration frontmatter can use this |
| Drift-test **runner** (see MECHANISM vs POLICY note below) | The grep+awk pattern comparing a SKILL.md version field to the latest migration to_version is a generic mechanism |
| Dispatcher (the `if [ -z "$FILTER" ]` pattern) | Generic filter-driven test-dispatch shape; consumer repos replace per-migration calls with their own functions |

### WORKFLOW set — stays in `claude-workflow`

These elements are tied to specific migration content or to GSD planning
artifacts; they have no use in `agenticapps-observability`:

| Element | Rationale |
|---------|-----------|
| `test_migration_0001()` through `test_migration_0021()` | Per-migration verify bodies testing specific 00NN migration content; claude-workflow specific |
| `test_meta_destinations_consistency()` | Tests observability-specific `meta.yaml` / adapter role tables in `add-observability/templates/`; not generic |
| `_roles_from_adapter()` / `_roles_from_meta()` | Helpers for the above; observability-specific |
| `test_sigterm_mid_apply_preserves_state()` | Tests the specific `migrate-0019-sentry-crons-and-healthz.sh` engine via hardcoded path; migration-0019-specific |
| `setup_fixture()` | Carved review (A1, codex HIGH): hardcodes claude-workflow template paths (templates/workflow-config.md, config-hooks.json, claude-md-sections.md) and a workflow-only 1.3.0 ADR special-case. Not reusable by agenticapps-observability as-is. Stays in claude-workflow as a thin WRAPPER that calls shared `extract_to` and layers the workflow specifics on top. |
| Drift-test **coupling POLICY** (see MECHANISM vs POLICY note below) | The specific rule "SKILL.md version == latest migration to_version" is claude-workflow-owned policy |

### MECHANISM vs POLICY (codex review finding)

The drift test (`test_skill_md_version_matches_latest_migration_to_version`)
has two separable concerns:

1. **MECHANISM (SHARED):** The runner — the generic grep+awk pattern that
   reads `skill/SKILL.md`, finds the highest-numbered migration file, reads
   its `to_version` field, and compares them. This mechanism is reusable by
   any repo that ships migrations with a `to_version` field and a SKILL.md
   with a `version` field. `agenticapps-observability` will need this pattern
   for its own drift enforcement.

2. **POLICY (WORKFLOW):** The specific version-coupling rule enforced:
   "the SKILL.md `version` field MUST equal the latest migration's
   `to_version`." This encodes claude-workflow's `versioning-tracks-migrations`
   discipline — the invariant that a SKILL.md version bump is only valid when
   a migration drives it. This is a repo-specific invariant, not a
   repo-agnostic universal law.

**Critical implication for SPLIT-01:** SPLIT-01 Phase C may extract the
runner mechanism to `agenticapps-shared`. However, the version-coupling
*policy* stays owned by the consumer repo. `agenticapps-observability` may
choose a different policy (e.g., semver-independent versioning); the shared
runner does not impose this repo's discipline on consumers. The consumer
repo instantiates the runner with its own SKILL.md path and migration
directory; the runner emits PASS/FAIL; the consumer repo owns the rule
that PASS is required for shipping.

The `# SHARED — drift-test RUNNER mechanism` annotation in `migrations/run-tests.sh`
with its inline `POLICY NOTE (ADR-0035)` comment is the line-level canonical
reference for this distinction.

### Canonical line-level boundary map

The `# SHARED` and `# WORKFLOW` annotations in `migrations/run-tests.sh`
are the canonical boundary map that SPLIT-01 Phase C executes against.
Do not treat this ADR's tables as more authoritative than the annotations
in the file — if they ever conflict, fix this ADR to match the annotated
file (the file has git blame; this ADR is narrative).

### A1 amendment (2026-06-02): setup_fixture demoted to WORKFLOW wrapper

**Trigger:** Cross-AI review (28-REVIEWS.md A1, codex HIGH, user-locked).

`setup_fixture` was originally listed in the SHARED set. The codex review found it hardcodes
claude-workflow template paths (`templates/workflow-config.md`, `config-hooks.json`,
`claude-md-sections.md`) and a workflow-only 1.3.0 ADR special-case (`run-tests.sh:131-133`).
Parameterizing only the skill name leaves hidden consumer coupling — `agenticapps-observability`
cannot reuse it, violating SC-5. It is therefore demoted to the WORKFLOW set.

The SHARED count drops from **9 to 8** elements. The WORKFLOW count rises from **20 to 21**.

`extract_to` remains SHARED as the truly-generic git-ref primitive. `setup_fixture` becomes
a claude-workflow WORKFLOW wrapper (built in plan 28-03) that calls shared `extract_to` and
layers the workflow-specific template paths and the 1.3.0 special-case on top.

The line-level canonical reference is the `# WORKFLOW` annotation above `setup_fixture()`
in `migrations/run-tests.sh` (updated as part of plan 28-01 Task 4). This ADR table now
matches that annotation.

## Consequences

- **SPLIT-01 Phase C is now mechanical.** Every function in
  `migrations/run-tests.sh` carries an explicit `# SHARED` or `# WORKFLOW`
  annotation. The SPLIT-01 executor reads the annotation and routes the
  function accordingly. No boundary judgment is required at extraction time.

- **`bin/gsd-tools.cjs` is out of scope for the split.** It does not exist
  in this repo. SPLIT-01's Phase C section referencing it is corrected by a
  `CORRECTION` blockquote (see `SPLIT-01-agenticapps-shared.md`).

- **Phase 27 preserves the cooling-off baseline.** No code is moved in Phase
  27. The annotations are comment-only; `bash migrations/run-tests.sh` exits
  with the same result as on the unannotated baseline. The SPLIT-00 7-day
  cooling-off clock is not reset.

- **`agenticapps-shared` will need its own drift test.** The shared runner
  mechanism lands in `agenticapps-shared`; `agenticapps-observability`
  instantiates it against its own SKILL.md. Each consumer repo owns its
  version-coupling policy; the shared repo ships the policy-agnostic runner.

## Rejected alternatives

| Alternative | Reason rejected |
|-------------|-----------------|
| **Extract `bin/gsd-tools.cjs` as planned in SPLIT-01** | That file does not exist in this repo; it is the GSD framework installed at `~/.claude/get-shit-done/bin/`. Extracting a non-existent file is a no-op. The original SPLIT-01 plan was based on a wrong premise. |
| **Defer boundary decision to SPLIT-01 execution time** | Increases Phase C risk (boundary judgment under time pressure). Pre-deciding in Phase 27 makes SPLIT-01 mechanical and eliminates the judgment call from the execution agent's critical path. |
| **Annotate `# SHARED` / `# WORKFLOW` as code comments inside function bodies** | The plan specifies comment-only additions as new lines above or adjacent to function declarations. Inline body annotations would be harder to grep for and risk co-mingling with functional code in diffs. |
| **Ship the policy in `agenticapps-shared`** | The version-coupling rule ("SKILL.md version == latest migration to_version") is a repo-specific invariant. Embedding it in shared infra would impose claude-workflow's discipline on all consumers, including observability, which may choose different versioning semantics. |

## References

- `migrations/run-tests.sh` — annotated file; the line-level canonical boundary map
- `SPLIT-01-agenticapps-shared.md` — CORRECTION note added in Phase 27 clarifying extraction target
- `SPLIT-00-PREREQUISITES.md` — downstream gate (pin-by-tag, D-07c); cooling-off conditions
- `.planning/phases/27-1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum-/27-CONTEXT.md` — D-06, D-06a, D-06b (boundary decisions); D-07c (gate fix)
- `versioning-tracks-migrations` — user rule: engine/test fixes to an existing migration get no version bump; no migration → no SKILL.md bump
- ADR-0033 (`docs/decisions/0033-with-queue-monitor.md`) — most recent prior ADR; 0035 follows the same header shape
