# Session Handoff — 2026-05-16 (Phase 17 PR open: #28)

On branch `feat/test-0001-baseline-fix-phase17`, branched from `main` at
`e5e9983`. Phase 17 changes are committed (5 atomic commits) and pushed to
`origin/feat/test-0001-baseline-fix-phase17`; PR #28 is open against `main`
awaiting review/merge. Working tree clean. Test-suite hygiene fix, no
scaffolder semantics moved.

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
- `bash migrations/run-tests.sh | grep '^[[:space:]]*✗'` → single line
  `✗ 03-no-gitnexus — exit 0, expected 1` (Phase 18 carry-over only).
- `bash .planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh` →
  Passed: 10 Failed: 0 with the tightened thresholds.

## Next session: start here

PR #28 is open: <https://github.com/agenticapps-eu/claude-workflow/pull/28>.
Branch is pushed; 5 atomic commits (`8f6b320 → 3a4c471`) plus one CodeRabbit
fix-up commit. Pick up by:

1. `gh pr view 28` — confirm CodeRabbit + CI green and the PR is mergeable.
2. `gh pr merge 28 --squash --delete-branch` — squash-merge per repo
   convention (every prior `main` commit has the `(#N)` suffix).
3. Locally: `git checkout main && git pull && git branch -D
   feat/test-0001-baseline-fix-phase17`.
4. Repoint `.planning/current-phase` to `phases/18-test-0007-fnm-path-fix`
   (or leave dangling until phase 18 opens) and refresh this handoff.

Atomic commits on the branch (for reference if needed):

- Commit A `8f6b320` — `migrations/run-tests.sh` fix (load-bearing).
- Commit B `c8190e2` — Phase 15 smoke threshold tighten.
- Commit C `9810d6d` — CHANGELOG `### Fixed` entry.
- Commit D `a752b16` — Phase 17 scaffolding (`PLAN.md` + `VERIFICATION.md`).
- Commit E `3a4c471` — session-handoff refresh.
- Commit F (CodeRabbit fix-up) — `\s` → `[[:space:]]` in smoke + this
  handoff's staged/unstaged contradiction resolved.

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
