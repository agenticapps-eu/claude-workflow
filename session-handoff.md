# Session Handoff — 2026-06-02

## Accomplished

- Executed plan 28-03 (consumer wiring — Wave 2 of SPLIT-01)
- Created feature branch `split-01-agenticapps-shared` off `plan/28-split-01`
- Added `vendor/agenticapps-shared` git submodule pinned by gitlink SHA `1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4` (A4 verified via `git ls-files -s`)
- Refactored `migrations/run-tests.sh` to source shared lib (D-28e source-and-keep); rebuilt `setup_fixture` as WORKFLOW wrapper (A1); replaced `test_preflight_verify_paths` and `test_skill_md_version_matches_...` with thin policy wrappers
- Confirmed `PASS=186 FAIL=4` hard gate preserved exactly; drift test PASS
- Proved A3 stale-gitlink advance: rewound submodule to HEAD~1, ran install.sh, confirmed it advanced back to `1f5d543`
- Proved A6 GSD non-regression: gsd-tools outputs byte-identical before/after refactor
- Updated `install.sh` with submodule sync+update block (A3)
- Added `[Unreleased] — SPLIT-01` section to `CHANGELOG.md`
- Pushed branch and opened **PR #65** to main with concrete body (A7)
- Created `28-03-SUMMARY.md`, updated `STATE.md` and `ROADMAP.md`

## Decisions

- A4 gitlink pin is the superproject gitlink SHA (not `git describe --tags`) — verified via `git ls-files -s vendor/agenticapps-shared`
- A1: `setup_fixture` stays in run-tests.sh as WORKFLOW wrapper, not in shared (codex HIGH, user-locked)
- A3: `install.sh` always runs sync+update when `.gitmodules` exists — no VERSION-missing guard
- A6 narrowed: captured `gsd-tools state` + `list-todos` (volatile timestamps stripped); diff empty

## Files modified

- `.gitmodules` — submodule declaration (new)
- `vendor/agenticapps-shared` — gitlink at 1f5d543 (new)
- `migrations/run-tests.sh` — sourcing block + WORKFLOW wrappers (refactored)
- `install.sh` — submodule sync+update block added
- `CHANGELOG.md` — [Unreleased] SPLIT-01 section added
- `.planning/phases/28-split-01-agenticapps-shared/28-03-SUMMARY.md` — created
- `.planning/STATE.md` — decisions + session update
- `.planning/ROADMAP.md` — plan progress updated

## Next session: start here

Plan 28-03 is at **Task 4 (human checkpoint)**. The PR #65 is open at
https://github.com/agenticapps-eu/claude-workflow/pull/65 on branch `split-01-agenticapps-shared`.

Human must:
1. Fresh-clone verify: `git clone --recurse-submodules <remote> /tmp/cw-fresh && [ -f /tmp/cw-fresh/vendor/agenticapps-shared/migrations/lib/helpers.sh ] && echo OK`
2. A4 confirm: `git -C /tmp/cw-fresh ls-tree HEAD vendor/agenticapps-shared` → 3rd field must equal `1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4`
3. Baseline: `bash migrations/run-tests.sh` in fresh clone → `PASS: 186  FAIL: 4`
4. Run `/gsd-review` (codex cross-AI, D-28f) and `/review` on the PR diff
5. Merge PR #65 when satisfied

After merge: branch `split-01-agenticapps-shared` can be deleted. Phase 28 SPLIT-01 is complete.
Next planned work is SPLIT-02 (agenticapps-observability) per `SPLIT-02-agenticapps-observability.md`.

## Open questions

- None blocking. The 4 pre-existing FAIL in test_migration_0017 remain FIX-0017-ENGINE scope (separate).
- `session-handoff.md` and the 3 untracked root noise files (FIX-0017-ENGINE.md, RESEARCH-cron-monitor-flush-fxsa.md, SPLIT-02-agenticapps-observability.md) are out of scope and NOT committed.
