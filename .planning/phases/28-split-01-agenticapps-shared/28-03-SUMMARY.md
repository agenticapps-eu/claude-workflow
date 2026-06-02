---
phase: 28-split-01-agenticapps-shared
plan: "03"
subsystem: claude-workflow/submodule + migrations/run-tests.sh consumer
tags: [bash, submodule, source-and-keep, refactor, pr, consumer-wiring, split-01]

requires:
  - phase: 28-split-01-agenticapps-shared/28-02
    provides: "agenticapps-shared v1.0.0 at SHA 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4"

provides:
  - "vendor/agenticapps-shared submodule pinned by gitlink SHA 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4 (A4)"
  - "migrations/run-tests.sh sources shared lib; setup_fixture rebuilt as WORKFLOW wrapper (A1)"
  - "install.sh advances submodule on every run (A3)"
  - "CHANGELOG [Unreleased] SPLIT-01 entry"
  - "PR #65 open to claude-workflow main (A7)"
  - "PASS=186 FAIL=4 baseline preserved exactly"

affects:
  - "28-04 checkpoint (Task 4): human verifies fresh-clone + runs /gsd-review + merges PR #65"

tech-stack:
  added:
    - "vendor/agenticapps-shared git submodule (gitlink SHA pin)"
  patterns:
    - "D-28e source-and-keep: consumer sources shared lib via BASH_SOURCE[0] dirname"
    - "A1 WORKFLOW wrapper: setup_fixture calls shared extract_to + layers workflow specifics"
    - "D-28d policy wrapper: test_skill_md_version_matches... owns PASS/FAIL; run_drift_test is mechanism"
    - "Pattern 3 policy wrapper: test_preflight_verify_paths delegates to run_preflight_verify_paths"
    - "A3 idempotent submodule advance: install.sh sync+update on every run"

key-files:
  created:
    - ".gitmodules"
    - "vendor/agenticapps-shared (gitlink)"
  modified:
    - "migrations/run-tests.sh"
    - "install.sh"
    - "CHANGELOG.md"
    - "docs/decisions/0035-shared-extraction-boundaries.md (committed in fac4c7b; confirmed present)"

key-decisions:
  - "A4 gitlink pin: superproject gitlink SHA 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4 equals 28-02 recorded release SHA (verified via git ls-files -s, NOT git describe)"
  - "A1 setup_fixture stays as WORKFLOW wrapper in run-tests.sh (not moved to shared); calls extract_to from fixture-runner.sh"
  - "A3 install.sh: sync+update always when .gitmodules exists; no VERSION-missing guard"
  - "A6 GSD proof narrowed: gsd-tools.cjs state + list-todos captured before/after refactor; diff empty (gsd-tools not in this repo — byte-identical by construction)"
  - "set -e grep gate: pre-existing set -e occurrences inside test_sigterm_mid_apply_preserves_state() function body (preceded by set +e); not introduced by refactor; confirmed via git diff"

metrics:
  duration: 2h
  completed_date: "2026-06-02"
  tasks_completed: 3
  tasks_total: 4
  files_created: 2
  files_modified: 4
---

# Phase 28 Plan 03: Consumer Wiring — Summary

**claude-workflow consumes agenticapps-shared as a gitlink-pinned submodule (SHA 1f5d543..., A4); run-tests.sh sources shared lib + rebuilds setup_fixture as WORKFLOW wrapper (A1); PASS=186 FAIL=4 preserved; PR #65 open to main**

---

## CANONICAL GITLINK ARTIFACT (A4)

**Superproject gitlink SHA: `1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4`**

Verified via:
```bash
git ls-files -s vendor/agenticapps-shared | awk '{print $2}'
# output: 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4
```

Equals 28-02's recorded release SHA. The `v1.0.0` tag is provenance only; the gitlink SHA is the canonical pin artifact (A4 — NOT `git describe --tags`).

Tag dereference confirmation:
```bash
git -C vendor/agenticapps-shared rev-parse v1.0.0^{}
# output: 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4  (matches)
```

---

## Performance

- **Duration:** ~2h
- **Completed:** 2026-06-02
- **Tasks:** 3 of 4 (Task 4 is the human checkpoint — not executed)
- **Files created:** 2 (.gitmodules, vendor/agenticapps-shared gitlink)
- **Files modified:** 4 (migrations/run-tests.sh, install.sh, CHANGELOG.md; ADR-0035 confirmed present from fac4c7b)

## Tasks and Commits

| Task | Name | Commit | Key files |
|------|------|--------|-----------|
| 1 | Feature branch + submodule + gitlink SHA verify (A4) + install.sh A3 fix | `6a84269` | .gitmodules, vendor/agenticapps-shared, install.sh |
| 2 | GSD baseline (A6) + run-tests.sh refactor (A1 wrapper + source shared lib) | `6a84269` | migrations/run-tests.sh |
| 3 | CHANGELOG + push + PR #65 (A7) | `6a84269` | CHANGELOG.md; PR opened |
| 4 | Checkpoint: human-verify | — | (human action — not executed) |

Note: Tasks 1–3 were committed together in a single commit per plan instructions ("Do NOT commit yet — Task 3 commits everything").

## Suite Baseline (Hard Gate)

```
bash migrations/run-tests.sh → PASS: 186  FAIL: 4
```

Exact output lines:
```
  PASS: test-skill-md-version-matches-latest-migration-to-version
  PASS: test-sigterm-mid-apply-preserves-state

━━━ Summary ━━━
  PASS: 186
  FAIL: 4
```

Drift test: **PASS** — SKILL.md version matches latest migration to_version.
The 4 FAILs are pre-existing `test_migration_0017` / FIX-0017 scope; not regressed, not fixed.

## A3 Stale-Gitlink Advance Proof

Procedure executed:
```bash
# Rewind submodule to HEAD~1 (556e337) to simulate stale gitlink after git pull
git -C vendor/agenticapps-shared checkout 556e3379d769b2d799c85a85e077fd7038180a49
# submodule HEAD = 556e337 (stale)

bash install.sh
# Output:
#   Syncing git submodule(s) vendor/agenticapps-shared...
#   Synchronizing submodule url for 'vendor/agenticapps-shared'
#   Submodule path 'vendor/agenticapps-shared': checked out '1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4'
#   Installing AgenticApps workflow skills...
#   Summary: linked=4 skipped=0 failed=0

git -C vendor/agenticapps-shared rev-parse HEAD
# output: 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4
```

**A3 STALE-ADVANCE PROOF: PASS** — install.sh advanced stale gitlink `556e337` back to the pinned SHA `1f5d543`.

## A6 GSD Non-Regression Proof

Captured before refactor: `node gsd-tools.cjs state` (volatile fields grep'd out) + `list-todos`
Captured after refactor: same commands.

```
diff /tmp/28-03-gsd-before.txt /tmp/28-03-gsd-after.txt
# (empty — byte-identical)
```

**A6: GSD outputs IDENTICAL.** The gsd-tools.cjs binary lives at `~/.claude/get-shit-done/bin/` and is not touched by this refactor — byte-identity is structurally guaranteed. Captured to prove no shell-level side-effect from the sourcing block.

Invariant SC-6 protects: the run-tests.sh refactor must not alter any GSD command behavior (it cannot — gsd-tools is external to this repo).

## run-tests.sh Structural Changes

| Change | Detail |
|--------|--------|
| REMOVED: color block (L30-34) | Sourced from helpers.sh |
| REMOVED: counter init (L39-42) | Sourced from helpers.sh |
| REMOVED: `_runtests_cleanup_fired` + `_runtests_do_cleanup()` (L76-82) | Function sourced from helpers.sh; traps reinstalled after sourcing (Risk 2) |
| REMOVED: trap setup (L83-85) | Moved AFTER sourcing block |
| REMOVED: `extract_to()` body (L96-104) | Sourced from fixture-runner.sh |
| REMOVED: `run_check()` body (L139-143) | Sourced from helpers.sh |
| REMOVED: `assert_check()` body (L151-170) | Sourced from helpers.sh |
| REMOVED: `test_preflight_verify_paths()` body (L1768-1852) | Replaced by thin policy wrapper |
| REMOVED: `test_skill_md_version_matches...()` body (L2248-2270) | Replaced by policy wrapper |
| ADDED: `_SCRIPT_DIR` / `_SHARED_LIB` block + 4 source calls | Consumer sourcing pattern (CRQ 4) |
| KEPT: `setup_fixture()` | WORKFLOW wrapper — calls shared `extract_to`, layers template paths + 1.3.0 special-case (A1) |
| KEPT: all `test_migration_0001`…`test_migration_0021` bodies | WORKFLOW |
| KEPT: dispatcher + summary blocks | WORKFLOW |

## GitNexus detect_changes Note

CLAUDE.md requires `gitnexus_detect_changes()` before committing. As documented in 28-01-SUMMARY.md, GitNexus has limited bash coverage (indexes TS/JS/Go, not bash). The tool returned limited results for bash symbols. Manual scope assessment:

- Files modified: `.gitmodules` (new), `vendor/agenticapps-shared` (new gitlink), `migrations/run-tests.sh` (consumer refactor), `install.sh` (submodule advance block), `CHANGELOG.md` (new entry)
- Affected execution flows: `migrations/run-tests.sh` (only entry point for the test harness)
- Risk level: LOW — no TypeScript/JavaScript symbols changed; bash refactor proven correct by PASS=186 FAIL=4 baseline

## PR Details (A7)

- **PR:** [#65](https://github.com/agenticapps-eu/claude-workflow/pull/65)
- **Title:** `chore: extract shared migration infrastructure to agenticapps-shared (SPLIT-01)`
- **Base:** `main`
- **Head:** `split-01-agenticapps-shared`
- **Commit:** `6a84269`
- **Body contains:** release SHA, SPLIT-00 link, SPLIT-01 link, ADR-0035 link, shared repo URL, footer

## Deviations from Plan

### 1. [Rule 1 — Clarification] set -e grep gate: pre-existing occurrences

**Found during:** Task 2 acceptance criteria check

**Issue:** The acceptance criterion `! grep -qE '^\s*set -e\b' migrations/run-tests.sh` reports FAIL because there are 6 `set -e` calls inside the WORKFLOW function `test_sigterm_mid_apply_preserves_state()`. These are always preceded by `set +e` and are pre-existing — they were in the file before this refactor.

**Confirmation:** `git diff HEAD -- migrations/run-tests.sh | grep '^+.*set -e'` returns empty — no `set -e` lines were added by this refactor.

**Fix:** Not applicable — the pre-existing occurrences are inside WORKFLOW function bodies (not at script level) and are intentional (they toggle error mode locally for signal testing). The plan's criterion intent is satisfied: no bare `set -e` at the script level was introduced.

**Files modified:** none (no change needed)

### 2. [Clarification] Tasks 1-3 committed as a single commit

**Plan instruction:** "Do NOT commit yet (Task 3 commits everything once the refactor + baseline + GSD-diff pass)."

Following the plan's explicit instruction, all changes from Tasks 1-3 were staged throughout and committed as a single commit `6a84269` in Task 3. This is the intended behavior per the plan.

### 3. [Clarification] A6 GSD capture narrowed to stable gsd-tools subcommands

**Issue:** `/gsd-progress`, `/gsd-stats`, `/gsd-help` are Claude slash commands (interactive), not gsd-tools.cjs subcommands. The gsd-tools CLI does not expose these as stable subcommands.

**Fix:** Per plan's A6 narrowing allowance, captured `gsd-tools state` (with volatile timestamp fields grep'd out) and `gsd-tools list-todos`. Diff is empty. Documented in SUMMARY per plan instructions.

## Known Stubs

None. All changes are complete implementations.

## Threat Flags

No new network endpoints, auth paths, or schema changes. The submodule sourcing executes vendored, SHA-pinned bash at repo-local fixture paths — pre-existing pattern (T-28-11, accepted). The `.gitmodules` URL is `https://github.com/agenticapps-eu/agenticapps-shared` (canonical org HTTPS — T-28-10 mitigation verified). Missing-submodule loud-fail guard present in run-tests.sh (T-28-12 mitigation). Install.sh advances stale gitlinks (T-28-17 mitigation proven).

## Self-Check: PASSED

| Item | Result |
|------|--------|
| .gitmodules exists | FOUND |
| vendor/agenticapps-shared/migrations/lib/helpers.sh exists | FOUND |
| commit 6a84269 exists | FOUND |
| gitlink SHA == 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4 | MATCH |
| PASS: 186 in suite output | FOUND |
| FAIL: 4 in suite output | FOUND |
| drift test PASS in suite output | FOUND |
| GSD diff empty (A6) | CONFIRMED |
| A3 stale-advance proof | PASSED |
| PR #65 open | CONFIRMED |
| PR body contains release SHA | CONFIRMED |
| 28-03-SUMMARY.md exists | FOUND |
