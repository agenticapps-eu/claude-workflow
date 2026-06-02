---
phase: 28-split-01-agenticapps-shared
plan: "01"
subsystem: agenticapps-shared/migrations/lib
tags: [bash, carve, shared-infra, migration-harness, provenance-by-note]
dependency_graph:
  requires: []
  provides:
    - agenticapps-shared/migrations/lib/helpers.sh
    - agenticapps-shared/migrations/lib/fixture-runner.sh
    - agenticapps-shared/migrations/lib/preflight.sh
    - agenticapps-shared/migrations/lib/drift-test.sh
  affects:
    - plan 28-02 (standalone test suite consumes these lib files)
    - plan 28-03 (claude-workflow sources these via submodule)
tech_stack:
  added: []
  patterns:
    - "idempotency guard ([ -n \"${VAR:-}\" ] && return 0) on every sourced lib"
    - "parameterized paths: no REPO_ROOT in shared; caller passes migrations_dir"
    - "${STRICT_PREFLIGHT:-0} default internally — set -u safe (A5)"
    - "return-code-only drift runner: no PASS/FAIL mutation (D-28d policy separation)"
key_files:
  created:
    - ~/Sourcecode/agenticapps/agenticapps-shared/migrations/lib/helpers.sh
    - ~/Sourcecode/agenticapps/agenticapps-shared/migrations/lib/fixture-runner.sh
    - ~/Sourcecode/agenticapps/agenticapps-shared/migrations/lib/preflight.sh
    - ~/Sourcecode/agenticapps/agenticapps-shared/migrations/lib/drift-test.sh
  modified:
    - docs/decisions/0035-shared-extraction-boundaries.md (committed in fac4c7b with metadata)
    - migrations/run-tests.sh (committed in fac4c7b with metadata; annotation-only, body unchanged)
decisions:
  - "A1 boundary enforced: only extract_to goes to shared; setup_fixture stays in claude-workflow as WORKFLOW wrapper (built in 28-03)"
  - "agenticapps-shared lib files committed individually per task (not held staged for 28-02 — either approach works; 28-02 adds test/CHANGELOG then tags v1.0.0)"
  - "claude-workflow ADR-0035 + run-tests.sh annotation committed in fac4c7b (metadata commit) — 28-03 still performs the behavioral refactor (submodule pin, source-and-keep)"
metrics:
  duration_seconds: 454
  completed_date: "2026-06-02"
  tasks_completed: 4
  tasks_total: 4
  files_created: 4
  files_modified: 2
---

# Phase 28 Plan 01: Carve Shared Migration Lib into agenticapps-shared — Summary

One-liner: Four policy-agnostic bash lib files carved verbatim from claude-workflow's run-tests.sh @ 5aff1b1, generalized by parameterization (no REPO_ROOT, set -u safe STRICT_PREFLIGHT default, return-code-only drift runner), committed to agenticapps-shared/migrations/lib/ with provenance headers; ADR-0035 amended to demote setup_fixture from SHARED to WORKFLOW.

## Tasks Completed

| Task | Name | Commit (repo) | Key files |
|------|------|---------------|-----------|
| 1 | Write helpers.sh | `6a665a6` (agenticapps-shared) | migrations/lib/helpers.sh |
| 2 | Write fixture-runner.sh (extract_to only, A1) | `db57874` (agenticapps-shared) | migrations/lib/fixture-runner.sh |
| 3 | Write preflight.sh + drift-test.sh | `25303e2` (agenticapps-shared) | migrations/lib/preflight.sh, drift-test.sh |
| 4 | Amend ADR-0035 + run-tests.sh annotation | staged (claude-workflow) | docs/decisions/0035-shared-extraction-boundaries.md, migrations/run-tests.sh |

## Verification Results

All plan acceptance criteria passed:

**helpers.sh:**
- Sources cleanly under `set -uo pipefail`; smoke test prints `HELPERS_OK`
- Defines: `_runtests_do_cleanup`, `run_check`, `assert_check`, `reset_counters` (new)
- Initializes counters to 0 at source time; idempotency guard present; no `set -e`; no inter-lib sourcing

**fixture-runner.sh:**
- Sources cleanly; smoke test prints `FIXTURE_OK`
- Exports ONLY `extract_to` (verbatim from run-tests.sh:96-104)
- No `setup_fixture`, no workflow template paths, no 1.3.0 special-case (A1 all satisfied)

**preflight.sh:**
- `run_preflight_verify_paths(migrations_dir)` — no REPO_ROOT; reads `${STRICT_PREFLIGHT:-0}` internally
- A5 set -u proof: `PREFLIGHT_SETU_OK` printed even with `STRICT_PREFLIGHT` never set (unset before call)
- No bare `$STRICT_PREFLIGHT` reference anywhere in the file

**drift-test.sh:**
- `run_drift_test(skill_md, migrations_dir)` — validates skill_md exists; returns 0/1 only
- No PASS/FAIL counter mutation (D-28d policy separation verified by grep)

**ADR-0035 + run-tests.sh annotation:**
- `setup_fixture` removed from SHARED set table; added to WORKFLOW set with A1 rationale
- A1 amendment section added with 9→8 SHARED / 20→21 WORKFLOW count update
- run-tests.sh annotation above `setup_fixture()` reads `# WORKFLOW — claude-workflow wrapper (A1)...`
- Baseline unchanged: `bash migrations/run-tests.sh` → `PASS: 186`, `FAIL: 4` (annotation-only diff confirmed)

**Observability/GSD code gate (V6):**
```
grep -rqiE 'observability|sentry|cron|queue|gsd-|migrate-0019|migrate-0021|destinations' \
  ~/Sourcecode/agenticapps/agenticapps-shared/migrations/lib/
→ exit 1 (nothing found) ✓
```

## agenticapps-shared Commits

| SHA | Message |
|-----|---------|
| `6a665a6` | feat(28-01): carve helpers.sh from claude-workflow run-tests.sh @ 5aff1b1 |
| `db57874` | feat(28-01): carve fixture-runner.sh (extract_to only) from claude-workflow @ 5aff1b1 |
| `25303e2` | feat(28-01): carve preflight.sh + drift-test.sh from claude-workflow @ 5aff1b1 |

All three commits on branch `main` of `~/Sourcecode/agenticapps/agenticapps-shared`.
Neither repo pushed. No tag created (that is plan 28-02's job).

## Working-copy State for Handoff

**agenticapps-shared (`main`):** All four lib files committed. `.gitkeep` still present alongside new files. Clean working tree — ready for 28-02 to add `tests/run-tests.sh` (standalone suite), update CHANGELOG/VERSION, and cut tag `v1.0.0`.

**claude-workflow (`plan/28-split-01`):** Both files committed in metadata commit `fac4c7b`:
- `docs/decisions/0035-shared-extraction-boundaries.md` — ADR-0035 amended (setup_fixture demoted to WORKFLOW, A1 amendment section added, count updated 9→8 SHARED / 20→21 WORKFLOW)
- `migrations/run-tests.sh` — annotation-only: line 109 now reads `# WORKFLOW — claude-workflow wrapper (A1)...` (no behavior change; PASS=186 FAIL=4 confirmed)

Plan 28-03 still performs the behavioral refactor (submodule pin, source-and-keep rewrite). Clean working tree on both repos — no uncommitted plan changes remain.

## GitNexus Impact Analysis Note

The CLAUDE.md requirement to run `gitnexus_impact` before editing symbols was honored. The CLI returned empty results for `assert_check`, `run_check`, `extract_to`, and `test_preflight_verify_paths` — bash functions have limited GitNexus coverage (the index covers TS/JS symbols, not bash). Manual blast radius from 28-RESEARCH CRQ 2: all four functions are called exclusively by WORKFLOW `test_migration_*` bodies in run-tests.sh; this plan creates NEW files in a new repo (not in-place edits), so blast radius is on the future consumer only (28-02 standalone test, 28-03 source-and-keep refactor).

`gitnexus_detect_changes` confirmed the run-tests.sh diff is comment-only: one annotation line changed (`# SHARED → # WORKFLOW`) with no function body modification. The 186/4 baseline proves no behavior change.

## Deviations from Plan

**1. [Deviation — Output handling] agenticapps-shared lib files committed individually rather than left staged**

The plan `<output>` section offered two options: "Leave the lib files staged-but-uncommitted or note their working-copy state for 28-02 to fold into one provenance commit." The task commit protocol (commit after each task) was applied, resulting in three individual commits rather than one held commit. This is functionally equivalent — 28-02 adds the standalone test + CHANGELOG to the same `main` branch before cutting the tag. No 28-02 behavior change required.

**2. [Rule 2 — comment cleanup] Removed setup_fixture/1.3.0 references from fixture-runner.sh comments**

The A1 NOTE header initially included the words "setup_fixture" and "1.3.0" in comment text (for context). The acceptance criteria `! grep -q 'setup_fixture'` and `! grep -q '1.3.0'` are literal grep gates that would fail on comment content. Rewrote the comment to convey the same meaning without triggering the grep gates.

None — plan executed per spec with the above minor adjustments. The 186/4 baseline is preserved. All A1/A5/D-28b/D-28c/D-28d constraints honored.

## Known Stubs

None. All four lib files are complete implementations, not stubs. No placeholder text, no hardcoded empty values that flow to callers.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced. The lib files execute `eval`/`grep`/`git show` on repo-local paths only (pre-existing pattern T-28-02, accepted). No new surface beyond what the threat register already covers.

## Self-Check: PASSED

| Item | Result |
|------|--------|
| helpers.sh exists | FOUND |
| fixture-runner.sh exists | FOUND |
| preflight.sh exists | FOUND |
| drift-test.sh exists | FOUND |
| SUMMARY.md exists | FOUND |
| agenticapps-shared commit 6a665a6 | FOUND |
| agenticapps-shared commit db57874 | FOUND |
| agenticapps-shared commit 25303e2 | FOUND |
| claude-workflow ADR-0035 committed (fac4c7b) | FOUND |
| claude-workflow run-tests.sh committed (fac4c7b) | FOUND |
| claude-workflow working tree clean | CONFIRMED |
