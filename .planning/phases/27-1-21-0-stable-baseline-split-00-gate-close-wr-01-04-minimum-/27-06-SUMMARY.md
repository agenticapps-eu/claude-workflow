---
phase: 27-1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum-
plan: "06"
subsystem: changelog, release
tags: [changelog, versioning, release, a2-tag-only, split-00, 1.21.0]

# Dependency graph
requires:
  - phase: 27-05
    provides: WR-04 openrouter buildSentryOptions wiring + byte-symmetry verification (all WR items now done)
  - phase: 27-01
    provides: WR-01 go-test counter fix
  - phase: 27-02
    provides: WR-02 supabase-edge _resetForTest fix
  - phase: 27-03
    provides: WR-03 buildSentryOptions unit tests
  - phase: 27-04
    provides: SPLIT-00 pin-by-tag gate fix, ADR-0035, boundary annotations
provides:
  - "CHANGELOG ## [1.21.0] release section documenting all WR-01..04, Phase 26 (promoted), PROJECT.md, ADR-0035, SPLIT doc fixes"
  - "Explicit versioning note: release tag v1.21.0 leads skill version (SKILL.md 1.20.0 — A2 tag-only)"
  - "Empty ## [Unreleased] header preserved above [1.21.0] for next cycle"
  - "Manual release action (git tag v1.21.0) documented and deferred to ship time"
affects:
  - SPLIT-00 gate (v1.21.0 tag must exist on main after PR merge)
  - downstream factiv repos (cparx, callbot, fx-signal-agent) upgrading to 1.21.0

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A2 (tag-only) release: CHANGELOG section + git tag; SKILL.md does not advance without a migration"
    - "Two-axis versioning: release/baseline tag (v1.21.0) vs skill version (1.20.0) documented explicitly"
    - "Empty ## [Unreleased] header preserved at top of CHANGELOG for next release cycle"

key-files:
  created: []
  modified:
    - CHANGELOG.md

key-decisions:
  - "A2 invariant enforced: SKILL.md stays 1.20.0, drift test GREEN, no VERSION file, no migration"
  - "Phase 26 [Unreleased] entries promoted into [1.21.0] Fixed section (no information lost)"
  - "Task 2 (git tag v1.21.0) deferred to ship time — manual release action after PR merges to main"
  - "SPLIT-00 gate note added to CHANGELOG: CHANGELOG section alone does not satisfy gate; tag on main required"

patterns-established:
  - "Release notes pattern: promote [Unreleased] into versioned section; preserve empty [Unreleased] header above"
  - "Versioning note pattern: document the release-tag-vs-skill-version distinction inline in each release section"

requirements-completed: [CHANGELOG-1210]

# Metrics
duration: 8min
completed: 2026-06-02
---

# Phase 27 Plan 06: CHANGELOG ## [1.21.0] + v1.21.0 tag (manual) Summary

**CHANGELOG ## [1.21.0] section written with all WR-01..04, Phase 26 fixed entries (promoted from [Unreleased]), PROJECT.md/ADR-0035/SPLIT doc references, and explicit A2 versioning note; git tag v1.21.0 deferred to ship time.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-06-02T10:44:09Z
- **Completed:** 2026-06-02T10:52:00Z
- **Tasks:** 1 of 2 complete (Task 2 deferred — manual release action)
- **Files modified:** 1 (CHANGELOG.md)

## Accomplishments

- Added `## [1.21.0] — stable baseline (SPLIT-00 gate) — 2026-06-02` section to CHANGELOG.md
- Promoted Phase 26 [Unreleased] Fixed entries (CR-D firewall, DUAL harness pin, TS1038, fail-fast) into the [1.21.0] section
- Documented all Phase 27 changes: WR-01..04 under Fixed/Added/Changed; PROJECT.md + ADR-0035 + boundary annotations; SPLIT-00/01 doc fixes
- Preserved empty `## [Unreleased]` header at top of CHANGELOG for next release cycle
- Included explicit versioning note distinguishing release/baseline tag `v1.21.0` from skill version `1.20.0` (A2 invariant, migration-locked-version policy, per PROJECT.md)
- Confirmed A2 invariants intact: SKILL.md unchanged at `1.20.0`, drift test `test-skill-md-version-matches-latest-migration-to-version` PASSES (exit 0), no VERSION file, no migration

## Task Commits

1. **Task 1: Add ## [1.21.0] CHANGELOG section (A2 tag-only)** - `841d1ef` (feat)
2. **Task 2: git tag v1.21.0** — DEFERRED (manual release action; see below)

**Plan metadata commit:** (docs commit follows — includes this SUMMARY.md, STATE.md, ROADMAP.md)

## Files Created/Modified

- `CHANGELOG.md` — new `## [1.21.0]` section (50 lines inserted, 16 removed from [Unreleased] conversion)

## Decisions Made

- **A2 invariants held strictly:** SKILL.md stays `1.20.0`, no VERSION file created, no migration added. Drift test GREEN throughout.
- **Phase 26 [Unreleased] promoted:** Rather than keeping Phase 26 changes in a nested sub-section, they were folded into the [1.21.0] Fixed section (under "Phase 26 — promoted from [Unreleased]") alongside Phase 27's Fixed/Added/Changed. This gives a single coherent release section.
- **Task 2 deferred to ship time:** The `git tag v1.21.0` is a manual release action that happens AFTER this phase's PR merges to `main`. It is NOT run during execute-phase on the feature branch.
- **SPLIT-00 gate note added inline:** The CHANGELOG explicitly states the section landing in the PR does not by itself satisfy the SPLIT-00 gate — the tag on `main` is required.

## Deviations from Plan

None — plan executed exactly as specified. Task 1 (CHANGELOG edit) completed fully. Task 2 is a `checkpoint:human-action` by design and deferred to ship time per the execution context instructions.

## Pending Manual Release Action — Task 2 (RELEASE-TAG)

**Requirement ID: RELEASE-TAG** — Status: PENDING (deferred to ship time)

After the Phase 27 PR merges to `main`, perform the following steps to complete the 1.21.0 baseline:

**Step 1 — Confirm suite is GREEN on the merge commit:**
```bash
bash add-observability/templates/run-template-tests.sh && bash migrations/run-tests.sh
```

**Step 2 — Create the annotated tag on the merge commit:**
```bash
git tag -a v1.21.0 -m "claude-workflow 1.21.0 — stable baseline (SPLIT-00 gate)"
git push origin v1.21.0
```

**Step 3 — Verify:**
```bash
git tag --list 'v1.21.0'       # must show v1.21.0
git describe --tags             # must point at the 1.21.0 merge commit
git show v1.21.0 --stat         # confirm it's on the correct merge commit
```

**Step 4 — SPLIT-00 cooling-off clock starts:**
After tagging, the SPLIT-00 gate's 7-day cooling-off period begins. Downstreams pin to `v1.21.0` (git tag + commit SHA — NOT SKILL.md version, which stays `1.20.0`).

**CRITICAL:** Do NOT bump `skill/SKILL.md` to `1.21.0` — the drift test would FAIL (A2 invariant).

**Resume signal (if re-entering plan execution):** Type `"tagged"` once v1.21.0 is created and pushed, or `"defer"` to ship the tag after the PR lands.

## Issues Encountered

None.

## User Setup Required

**Manual release action required at ship time.** See "Pending Manual Release Action — Task 2" above. No external service configuration needed beyond the git tag creation.

## Next Phase Readiness

- Phase 27 is complete pending the manual `git tag v1.21.0` after PR merge
- All WR-01..04 closed; PROJECT.md, ADR-0035, SPLIT docs, CHANGELOG all in place
- SPLIT-00 gate satisfied (workflow-side) once the tag exists on `main` and 7-day cooling-off completes
- No blockers for PR creation and review

## Known Stubs

None — CHANGELOG.md is documentation only. No data sources, no UI components.

## Threat Flags

None — CHANGELOG.md edit introduces no new network endpoints, auth paths, file access patterns, or schema changes.

---

## Self-Check: PASSED

- `CHANGELOG.md` exists with `## [1.21.0]` section: FOUND
- `## [Unreleased]` preserved above `## [1.21.0]`: FOUND (line 7 vs line 9)
- All WR-01..04 referenced: FOUND (`grep -E 'WR-0[1-4]' CHANGELOG.md` matches all four)
- 1.20.0 referenced in [1.21.0] section: FOUND (versioning note)
- `skill/SKILL.md` version: `1.20.0` (UNCHANGED)
- Drift test: PASS (exit 0)
- No VERSION file: CONFIRMED
- Task 1 commit `841d1ef`: EXISTS
- No git tag v1.21.0 created: CONFIRMED (deferred per plan)

---
*Phase: 27-1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum-*
*Completed: 2026-06-02*
