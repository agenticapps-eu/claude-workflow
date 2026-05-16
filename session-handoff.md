# Session Handoff — 2026-05-16 (Phase 17 in progress on branch)

On branch `feat/test-0001-baseline-fix-phase17`, branched from `main` at
`e5e9983`. Working tree has Phase 17 changes staged for commit (test-suite
hygiene fix, no scaffolder semantics moved).

## Accomplished

- **Phase 15 fully shipped + merged** (carried from prior session) —
  `e5e9983 feat: ship init procedure + slash discovery (v1.11.0) (#27)` on
  main. PR #27 squash-merged; #22, #26 auto-closed; #24 remains OPEN for
  upstream `agenticapps-workflow-core` README touchup.
- **Phase 17 implemented on branch** — `test_migration_0001` baseline-anchor
  regression fixed in `migrations/run-tests.sh`. The legacy
  `git merge-base HEAD origin/main` resolved to HEAD when running on `main`
  post-merge, so both fixtures got the post-0001 template state and the 8
  "needs apply on v1.2.0" assertions failed. Replaced with a self-locating
  lookup: `before_ref` = parent of the commit that first introduced
  `## Backend language routing` in `templates/workflow-config.md` (resolves
  to `7dafa63`, the v1.2.0 baseline). Legacy merge-base chain retained as a
  fallback for stripped clones / pre-merge feature branches.
- **Phase 15 smoke regression-guard tightened** in lockstep —
  `PASS≥122 FAIL≤9` → `PASS≥130 FAIL≤1`; the `0001 carry-over` clause is
  removed from the known-fail allowlist; only the Phase 18 `03-no-gitnexus`
  clause remains.
- **`CHANGELOG.md`** — `### Fixed` entry added under `[1.11.0]`.
- **Phase 17 scaffolding** — `.planning/phases/17-test-0001-baseline-fix/`
  with `PLAN.md` + `VERIFICATION.md` (10-row evidence ledger).
  `.planning/current-phase` repointed from phase 15 to phase 17.

## Decisions

- **Test-only fix; no scaffolder version bump.** Migration 0001 semantics
  unchanged; templates unchanged; skill files unchanged. The change is to
  `run-tests.sh:test_migration_0001` and the Phase 15 smoke regression
  guard only. CHANGELOG `### Fixed` entry under `[1.11.0]` is the right home.
- **Dynamic marker lookup over hardcoded SHA.** Looked up `before_ref` via
  `git log --reverse -S '## Backend language routing'` rather than pinning to
  `7dafa63` to survive any future history rewrites that keep the marker
  intact. Hardcoded fallback path remains for the marker-absent case.
- **Tightened smoke thresholds same PR.** Locking in the new baseline now
  (PASS≥130 FAIL≤1) prevents regressions from sliding back into the
  carry-over allowlist. Skipping this would leave the smoke happy with a
  re-broken 0001 stanza.

## Files modified

- `migrations/run-tests.sh` — `test_migration_0001` `before_ref` block
  replaced (lines ~114-141). Legacy merge-base chain preserved as fallback.
- `.planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh` —
  regression-guard thresholds + known-fail allowlist updated.
- `CHANGELOG.md` — `### Fixed` entry added under `[1.11.0]`.
- `.planning/phases/17-test-0001-baseline-fix/PLAN.md` (NEW).
- `.planning/phases/17-test-0001-baseline-fix/VERIFICATION.md` (NEW).
- `.planning/current-phase` symlink → `phases/17-test-0001-baseline-fix`.
- `session-handoff.md` — this file.

## Verification

- `bash migrations/run-tests.sh | tail -3` → **PASS=130 FAIL=1** (was 122/9).
- `bash migrations/run-tests.sh | grep '^\s*✗'` → single line
  `✗ 03-no-gitnexus — exit 0, expected 1` (Phase 18 carry-over only).
- `bash .planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh` →
  Passed: 10 Failed: 0 with the tightened thresholds.

## Next session: start here

Commits are not yet on the branch (the local edits are unstaged). Pick up by:

1. `git status` — confirm the 5 modified files + 3 new files listed above.
2. `git add` + atomic commits per phase convention. Suggested split:
   - Commit A: `migrations/run-tests.sh` fix (the load-bearing change).
   - Commit B: Phase 15 smoke threshold tighten.
   - Commit C: CHANGELOG `### Fixed` entry.
   - Commit D: Phase 17 scaffolding (`PLAN.md` + `VERIFICATION.md` +
     `current-phase` symlink repoint).
   - Commit E: session-handoff refresh.
3. `git push -u origin feat/test-0001-baseline-fix-phase17` and `gh pr create`
   against `main`. PR body should link Phase 18 as the obvious follow-up and
   note the test-only / no-version-bump scope.
4. After merge, repoint `.planning/current-phase` to phase 18 (or leave
   dangling) and refresh handoff.

## Open questions (carried forward)

- **Phase 18** — `test_migration_0007` `03-no-gitnexus` fnm-PATH leak. Single
  remaining suite failure. Likely the next phase after #17 lands.
- **Phase 19** — `--strict-preflight` flag for Phase 13 audit.
- **Issue #24** — spec v0.3.0 adoption stays OPEN until upstream
  `agenticapps-workflow-core/reference-implementations/README.md` row is
  updated. Cross-repo task.
- **Issue #5** — older v0.1.0 bootstrap issue, probably subsumable by #24.
  Triage candidate.
- **Init harness expansion** — VERIFICATION.md F4 (phase 15) flagged the 7
  init fixture pairs as reference-only at v1.11.0. A future phase could add
  `test_init_fixtures()` to `run-tests.sh`.
- **Cross-tree `applies_to` framework hardening** — migration 0012's
  `~/.claude/skills/...` reference flagged as a new precedent worth a
  framework-level `host_paths:` allowlist.
- **REDACTED_KEYS default expansion** — defer to a v0.3.2 minor of
  `add-observability`.
- **Anchor-comment threat-model documentation** — one-paragraph addition to
  INIT.md "Important rules".
- **Carried from prior sessions** (unchanged): fx-signal-agent v1.10.0
  adoption verification; helper-script license consent for
  `index-family-repos.sh --all`; canonical install command for `/gsd-review`;
  CHANGELOG hygiene to stamp `[1.9.3]` as released.
