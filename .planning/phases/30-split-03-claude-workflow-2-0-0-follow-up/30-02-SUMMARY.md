---
phase: 30-split-03-claude-workflow-2-0-0-follow-up
plan: 02
subsystem: migrations
tags: [migration, observability-repoint, phase-sentinel, 2.0.0, drift-test, tdd]
requires:
  - 30-01 (deletion wave; 7 tombstones; 0021 tombstone chain endpoint to_version 1.20.0; suite PASS 143)
provides:
  - migration 0022 (observability repoint + 2.0.0 + #58 hook swap)
  - templates/.claude/hooks/phase-sentinel.sh (deterministic Stop hook)
  - skill/SKILL.md version 2.0.0 (drift GREEN)
  - test_migration_0022 + test_phase_sentinel + 0022 fixtures
affects:
  - downstream /update path (1.20.0/1.21.0 -> 2.0.0)
  - templates consumed by /setup-agenticapps-workflow (new projects)
tech-stack:
  added: []
  patterns:
    - "supersede-without-mutate (0022 supersedes 0011 install step; 0011 byte-unchanged)"
    - "positive idempotency anchors (assert desired end-state PRESENT, not old text absent)"
    - "atomic drift bump (0022 to_version + SKILL.md version in one commit)"
    - "abort-if-absent pre-flight (exit 3, no auto-install — D-03)"
key-files:
  created:
    - templates/.claude/hooks/phase-sentinel.sh
    - migrations/0022-observability-repoint-phase-sentinel.md
    - migrations/test-fixtures/0022/01-repoint-and-hookswap/{setup,verify}.sh + expected-exit
    - migrations/test-fixtures/0022/02-abort-when-skill-absent/{setup,verify}.sh + expected-exit
    - migrations/test-fixtures/0022/03-idempotent-reapply/{setup,verify}.sh + expected-exit
    - migrations/test-fixtures/0022/common-setup.sh
  modified:
    - templates/claude-settings.json
    - skill/SKILL.md
    - migrations/run-tests.sh
decisions:
  - "0022 Step 4 targets the CANONICAL hyphenated .claude/skills/agentic-apps-workflow/SKILL.md (per 0011 applies_to + install.sh:42) — not the non-hyphenated dev-clone form"
  - "obs-skill audit FAIL on dev machine is informational-only (loose mode by design, D-03 separate-install); strict mode for CI parity"
metrics:
  duration: ~25m
  completed: 2026-06-03
  commits: 3
  tasks: 3
  files_created: 11
  files_modified: 3
  pass_baseline_before: 143
  pass_baseline_after: 149
---

# Phase 30 Plan 02: Migration 0022 — Observability Repoint + 2.0.0 + Phase Sentinel Hook Summary

Added migration 0022 — the single breaking-cleanup migration that repoints the observability install from the in-repo `add-observability` skill to the separately-installed `observability` skill (abort-if-absent, exit 3, no auto-install), folds in the GH #58 deterministic `phase-sentinel.sh` Stop-hook swap, and bumps claude-workflow to 2.0.0 — plus the new template hook and TDD test bodies, with `skill/SKILL.md` bumped to 2.0.0 atomically so the drift test stays GREEN.

## What Was Built

| Task | Deliverable | Commit |
|------|-------------|--------|
| 1 | `phase-sentinel.sh` template (executable) + `claude-settings.json` Stop block swap (Haiku prompt -> type:command) | `c5ba2e9` |
| 2 | migration 0022 (repoint + abort-if-absent + #58 hook steps + canonical hyphenated version-bump, to_version 2.0.0) + `skill/SKILL.md` 1.20.0 -> 2.0.0 (same commit) | `d631127` |
| 3 | 0022 fixtures (3) + `test_migration_0022` + `test_phase_sentinel` + dispatcher stanzas | `4211de5` |

## Key Facts (required SUMMARY records)

- **New PASS baseline:** 149 (was 143). FAIL 0, suite exit 0. The +6 = 3 phase-sentinel cases + 3 `0022` fixtures.
- **Drift before/after:** Before this plan the drift test read the 0021 tombstone's `to_version: 1.20.0` == `skill/SKILL.md 1.20.0` (GREEN). After Task 2, `0022-*.md` is the alphabetically-last migration file → drift reads its `to_version: 2.0.0` == `skill/SKILL.md 2.0.0` (GREEN). The bump was atomic (Pitfall 3): 0022 + SKILL.md in one commit, so drift was never RED between commits.
- **0011 byte-unchanged:** Confirmed via `git diff --quiet migrations/0011-observability-enforcement.md` (exit 0) after each task and at plan end. 0022 supersedes 0011's install step semantically; 0011 was never touched.
- **Canonical hyphenated version-bump path used:** 0022 Step 4 (idempotency + pre-condition + apply + post-check) all target `.claude/skills/agentic-apps-workflow/SKILL.md` (HYPHENATED), per 0011 `applies_to` line 8 + `install.sh:42` skill-name `agentic-apps-workflow`. The non-hyphenated `agenticapps-workflow` dev-clone form (which would silently no-op the bump) was deliberately avoided.
- **jq filter used for the Stop swap (Step 3):**
  ```
  .hooks.Stop = (
    [ .hooks.Stop[]
      | select(( [ .hooks[]?
          | select(.type? == "prompt"
                   and ((.prompt? // "") | test("current-phase/checklist.md"))) ]
        | length ) == 0)
    ]
    + [ { "_hook": "Hook 3 — Phase Sentinel (deterministic shell)",
          "hooks": [ { "type":"command",
                       "command":"$CLAUDE_PROJECT_DIR/.claude/hooks/phase-sentinel.sh",
                       "timeout":5000 } ] } ]
  )
  ```
  This drops only the entry whose inner hook is `type=="prompt"` AND whose prompt matches `current-phase/checklist.md` (Pitfall 5: narrow selector), then appends the deterministic command entry. Validated against the real pre-swap settings shape: prompt removed, command present, Stop length 1, PreToolUse (2) intact.

## Verification Results

- `bash migrations/run-tests.sh` → FAIL 0, exit 0, PASS 149.
- `bash migrations/run-tests.sh phase-sentinel` → 3/3 PASS (exit 0 / 0 / 2).
- `bash migrations/run-tests.sh 0022` → 3/3 PASS.
- `bash migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version` → PASS (2.0.0 == 2.0.0).
- Step 3 jq filter dry-run against the real old `claude-settings.json` shape: command hook present, prompt removed, other hooks intact.

## TDD Discipline (Task 3)

- RED observed: with test bodies + dispatcher added but the `migrations/test-fixtures/0022/` dir absent, `test_migration_0022` reported `SKIP: fixtures directory missing` (PASS 0). `test_phase_sentinel` was already GREEN because the template hook from Task 1 exists.
- GREEN reached: authored the 3 fixtures → `0022` reports 3/3 PASS; full suite FAIL 0.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `git add` of new `templates/.claude/...` file blocked by `.gitignore`**
- **Found during:** Task 1
- **Issue:** `.gitignore:9` ignores `.claude/`, so `git add templates/.claude/hooks/phase-sentinel.sh` was rejected. The existing template hooks (session-bootstrap.sh etc.) are already tracked, which is why they are unaffected.
- **Fix:** used `git add -f` for the new template hook file (and likewise for the new `test-fixtures/0022/` files which contain `.claude/`-named paths in fixture scripts), matching the established pattern for these intentionally-version-controlled template/fixture artifacts.
- **Files modified:** staging only (no content change).
- **Commit:** `c5ba2e9`, `4211de5`

### Notes (not deviations)

- The pre-flight audit reports `FAIL=2` (informational-only, loose mode, NOT in suite totals): `0008` (curl to a local coverage server not running on dev machine, pre-existing) and `0022` (obs-skill `requires.verify` failing because the `observability` skill is not installed on this dev machine). The 0022 audit FAIL is exactly the D-03 design — separate install; the audit's loose-mode default exists precisely so a missing host dependency does not trip the harness. Strict mode (`--strict-preflight`) is for CI parity environments where the obs skill is installed.

## Known Stubs

None. The fixtures use synthetic sandbox state (a stub `observability/SKILL.md` and project skeleton) which is the standard hermetic-fixture pattern, not a product stub. No placeholder data flows to any UI or runtime.

## Self-Check: PASSED

- `templates/.claude/hooks/phase-sentinel.sh` — FOUND (mode 100755)
- `migrations/0022-observability-repoint-phase-sentinel.md` — FOUND
- `migrations/test-fixtures/0022/` (3 fixtures + common-setup.sh) — FOUND
- `skill/SKILL.md` version 2.0.0 — FOUND
- Commits `c5ba2e9`, `d631127`, `4211de5` — FOUND
