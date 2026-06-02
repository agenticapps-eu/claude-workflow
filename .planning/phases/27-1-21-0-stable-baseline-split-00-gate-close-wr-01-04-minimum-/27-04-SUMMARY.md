---
phase: 27
plan: "04"
subsystem: split-prep
tags: [audit, annotation, adr, split-prep, documentation]
dependency_graph:
  requires: []
  provides:
    - migrations/run-tests.sh SHARED/WORKFLOW annotations (canonical boundary map for SPLIT-01 Phase C)
    - ADR-0035 (shared extraction boundary record, Status: Accepted)
    - SPLIT-01-agenticapps-shared.md CORRECTION note (gsd-tools.cjs premise corrected)
    - SPLIT-00-PREREQUISITES.md pin-by-tag gate fix (D-07c) + downstream-evidence rule
  affects:
    - SPLIT-01 Phase C execution (now mechanical — read annotations, not plan prose)
    - SPLIT-00 gate checklist (now satisfiable under A2; SKILL.md stays 1.20.0)
tech_stack:
  added: []
  patterns:
    - "# SHARED / # WORKFLOW annotation convention for split-prep boundary marking"
    - "ADR pattern: Status/Date/Phase header → Context → Decision → Consequences → Rejected alternatives → References"
key_files:
  created:
    - docs/decisions/0035-shared-extraction-boundaries.md
  modified:
    - migrations/run-tests.sh (42 comment-only insertions, 0 deletions)
    - SPLIT-01-agenticapps-shared.md (CORRECTION blockquote added)
    - SPLIT-00-PREREQUISITES.md (pin-by-tag gate + downstream-evidence rule)
decisions:
  - "SHARED set for migrations/run-tests.sh: _runtests_do_cleanup, extract_to, setup_fixture, run_check, assert_check, preflight auditor, drift-test runner mechanism, dispatcher"
  - "WORKFLOW set: all per-migration test functions (0001-0021), meta.yaml consistency test, _roles_from_* helpers, SIGTERM test"
  - "MECHANISM vs POLICY: drift-test runner is SHARED infra; version-coupling rule is WORKFLOW-owned policy (stays in consumer repo)"
  - "bin/gsd-tools.cjs is the GSD framework, not this repo — out of scope for claude-workflow split"
  - "SPLIT-00 gate changed from SKILL.md version check to pin-by-tag (v1.21.0 / commit SHA)"
  - "Downstream-evidence rule: installed SKILL.md version is not acceptable proof of 1.21.0 baseline"
metrics:
  duration_minutes: 9
  completed_date: "2026-06-02"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 4
---

# Phase 27 Plan 04: Split-prep groundwork — audit + annotate + document Summary

**One-liner:** Comment-only boundary annotations on `migrations/run-tests.sh` (9 SHARED / 20 WORKFLOW markers) + ADR-0035 capturing the canonical boundary + SPLIT-01 premise correction (target is run-tests.sh, not gsd-tools.cjs) + SPLIT-00 gate fixed to pin-by-tag (satisfiable under A2).

## What Was Built

### Task 1: Annotate `migrations/run-tests.sh`

Added 42 comment-only lines (9 `# SHARED`, 20 `# WORKFLOW` markers — some sections have multi-line annotation blocks) across all major sections and functions:

**SHARED annotations (9):**
- `_runtests_do_cleanup` — generic signal-trap harness lifecycle
- Helpers section header — generic section label
- `extract_to` — generic git-ref extraction utility
- `setup_fixture` — generic fixture-runner harness
- `run_check` — generic pass/fail check runner
- `assert_check` — generic assertion helper with PASS/FAIL counters
- `test_preflight_verify_paths` — generic verify-path auditor
- `test_skill_md_version_matches_latest_migration_to_version` — drift-test RUNNER mechanism (with inline POLICY NOTE cross-referencing ADR-0035)
- Dispatcher — generic filter-driven dispatch pattern

**WORKFLOW annotations (20):**
- `test_migration_0001` through `test_migration_0021` (14 per-migration functions)
- `test_meta_destinations_consistency` + `_roles_from_adapter` + `_roles_from_meta` (observability-specific role-table checks)
- `test_sigterm_mid_apply_preserves_state` (hardcoded to migration 0019 engine path)

**Verification:**
- `git diff --stat migrations/run-tests.sh`: 1 file, 42 insertions, 0 deletions (comment-only)
- `bash migrations/run-tests.sh`: drift test `test_skill_md_version_matches_latest_migration_to_version` PASS; SKILL.md stays 1.20.0; same 4 pre-existing failures as baseline (unchanged)

### Task 2: ADR-0035 + SPLIT-01 correction + SPLIT-00 gate fix

**ADR-0035** (`docs/decisions/0035-shared-extraction-boundaries.md`):
- Status: Accepted
- Defines SHARED/WORKFLOW boundary with boundary test verbatim
- Corrects Blocker B: `bin/gsd-tools.cjs` is the GSD framework, not this repo
- Explicitly separates drift-test MECHANISM (SHARED) from version-coupling POLICY (WORKFLOW)
- Names the line-level annotations as the canonical boundary map

**SPLIT-01-agenticapps-shared.md:**
- Added `> **CORRECTION (Phase 27, ADR-0035):**` blockquote at top of "Shared GSD-tools subset" section
- States the extraction target is `migrations/run-tests.sh` + migration content, NOT `bin/gsd-tools.cjs`
- Struck through superseded gsd-tools.cjs content; points to ADR-0035

**SPLIT-00-PREREQUISITES.md:**
- Changed all three downstream gate lines (cparx, callbot, fx-signal-agent) from `SKILL.md version: 1.21.0` to pin-by-tag: git tag `v1.21.0` / commit SHA
- Added one-line rationale referencing D-07/A2 (SKILL.md stays 1.20.0 under A2)
- Added `DOWNSTREAM-EVIDENCE RULE` blockquote: each downstream must record source tag + commit SHA as proof-of-baseline; explicitly states installed `SKILL.md version` is NOT acceptable evidence of the 1.21.0 baseline

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | `248bdba` | `chore(27-04): annotate migrations/run-tests.sh with # SHARED / # WORKFLOW (audit-only)` |
| Task 2 | `ccf1a72` | `docs(27-04): write ADR-0035 + correct SPLIT-01 premise + fix SPLIT-00 gate to pin-by-tag` |

## Deviations from Plan

None — plan executed exactly as written.

The plan's planned annotation points (lines ~76, ~92, ~105, ~133, ~144, ~1746, ~1942, ~2210, ~2243) matched the actual structure. Exact line numbers shifted slightly due to prior phase commits but all functions were found and annotated correctly.

## Known Stubs

None. This plan is documentation/annotation only; no UI rendering, no data sources, no placeholder text.

## Threat Flags

None. Comment-only annotations to a bash script plus documentation edits. No new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| `migrations/run-tests.sh` exists | FOUND |
| `docs/decisions/0035-shared-extraction-boundaries.md` exists | FOUND |
| `SPLIT-01-agenticapps-shared.md` exists | FOUND |
| `SPLIT-00-PREREQUISITES.md` exists | FOUND |
| `27-04-SUMMARY.md` exists | FOUND |
| Commit `248bdba` exists | FOUND |
| Commit `ccf1a72` exists | FOUND |
| `# SHARED` count ≥ 5 | 9 |
| `# WORKFLOW` count ≥ 1 | 20 |
| ADR-0035 Status: Accepted | OK |
| SPLIT-01 CORRECTION present | OK |
| SPLIT-00 v1.21.0 pin-by-tag present | OK |
