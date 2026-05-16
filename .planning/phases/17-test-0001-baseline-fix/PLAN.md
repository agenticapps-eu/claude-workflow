# Phase 17 — `test_migration_0001` baseline-anchor fix

## Goal

Resolve the 8 step-idempotency failures in `test_migration_0001` so the full
migration test suite reaches **PASS=130 / FAIL=1** (down from the carry-over
baseline of PASS=122 / FAIL=9). The remaining single failure is the Phase 18
target (`test_migration_0007` `03-no-gitnexus` fnm-PATH leak).

## Problem

`test_migration_0001` in `migrations/run-tests.sh` synthesizes a "before"
fixture from `git merge-base HEAD origin/main` and an "after" fixture from
`HEAD`. The intent: the before fixture represents v1.2.0 pre-migration state
and the after fixture represents v1.3.0 post-migration state.

When the test is run on `main` itself (post-merge of migration 0001), the
merge-base resolves to HEAD, so both fixtures get the **same** post-migration
template state. The 8 "needs apply on v1.2.0" assertions then fail because the
"before" fixture already contains the post-migration markers.

This produced 8 of the 9 known carry-over failures since v1.3.0 was merged.

## Fix

Anchor `before_ref` to the **parent of the commit that first introduced
migration 0001's marker** (`## Backend language routing`) in
`templates/workflow-config.md`. Resolved dynamically via:

```bash
marker_commit="$(git log --reverse --format=%H -S '## Backend language routing' -- templates/workflow-config.md | head -1)"
before_ref="$(git rev-parse "${marker_commit}^")"
```

Concretely this resolves to `7dafa63` (parent of `b21abc6` / squash of PR #2),
which IS the v1.2.0 pre-migration state. The lookup is self-locating and
works on any branch — feature branches that haven't merged 0001 yet still
fall back to the legacy `git merge-base HEAD origin/main` chain if the marker
isn't reachable from HEAD (handled by an explicit `[ -z "$before_ref" ]`
fallback block).

## Scope

- `migrations/run-tests.sh:test_migration_0001` — replace `before_ref` block
  with the marker-anchored lookup + fallback.
- `.planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh` —
  tighten the regression-guard thresholds from `PASS≥122 FAIL≤9` to
  `PASS≥130 FAIL≤1` and remove the now-resolved `0001 carry-over` clause
  from the known-fail allowlist. The remaining clause covers Phase 18.
- `CHANGELOG.md` — add `### Fixed` entry under `[1.11.0]`.

## Out of scope

- Phase 18 (`test_migration_0007` `03-no-gitnexus` fnm-PATH leak).
- Scaffolder version bump. Test-harness hygiene only; no migration semantics
  or scaffolder-visible behaviour changes.
- Refactoring other tests' before-ref logic. `test_migration_0001` is the
  only test using merge-base-based extraction; all other tests use either
  hand-built fixtures (0009, 0010, …) or extract templates from HEAD.

## Verification

- `bash migrations/run-tests.sh` → PASS=130 FAIL=1, the single FAIL being
  `03-no-gitnexus — exit 0, expected 1` (Phase 18 carry-over).
- `bash .planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh` →
  Passed: 10 Failed: 0, with the tightened thresholds.
- Manual sanity check: `git log -1 --format='%h %s' "$(git log --reverse \
  --format=%H -S '## Backend language routing' -- \
  templates/workflow-config.md | head -1)^"` resolves to
  `7dafa63 feat: enforcement plan — commitment ritual + gate-to-skill map (#1)`.
