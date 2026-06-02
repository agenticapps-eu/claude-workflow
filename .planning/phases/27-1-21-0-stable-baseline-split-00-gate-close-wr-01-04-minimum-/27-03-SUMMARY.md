---
phase: 27-1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum-
plan: "03"
subsystem: planning
tags: [project-md, state, roadmap, versioning, split-prep, documentation]

# Dependency graph
requires:
  - phase: 27-1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum-
    provides: Phase 27 planning artifacts (CONTEXT.md, SPLIT-00/01/02 docs)

provides:
  - Canonical .planning/PROJECT.md (D-05 minimum-viable, forward-looking)
  - Drift-refreshed STATE.md (Phase 26 merged, Phase 27 position, stale Next action fixed)
  - Drift-refreshed ROADMAP.md (Phase 26 marked shipped+merged, v1.21.0 milestone added)

affects:
  - 27-04 (SPLIT-01 correction — references PROJECT.md for split rationale)
  - 27-05 (WR-04 — STATE.md now points at existing PROJECT.md)
  - 27-06 (CHANGELOG — versioning policy section in PROJECT.md defines 1.21.0 framing)
  - SPLIT-00 gate audit (PROJECT.md resolves the "does not yet exist" blocker)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Two-axis version model: release/baseline tag (v1.21.0) vs migration-coupled skill version (1.20.0)"
    - "Tag-only release strategy (A2): skill version trails until next migration"

key-files:
  created:
    - .planning/PROJECT.md
  modified:
    - .planning/STATE.md
    - .planning/ROADMAP.md

key-decisions:
  - "PROJECT.md is forward-looking only — no phase retro; history stays in .planning/phases/ + git"
  - "Versioning policy section defines the release/baseline-tag vs skill-version split explicitly to prevent dual-version confusion in downstreams"
  - "ROADMAP.md milestone for v1.20.x marked shipped (PR #60, 46bb394); new v1.21.0 milestone entry added"
  - "STATE.md Next action updated to reflect Phase 27 remaining plans (27-05, 27-06)"

patterns-established:
  - "PROJECT.md pattern: product identity doc is forward-looking, links to phases/ for history"
  - "Versioning terminology: always use 'release/baseline tag' and 'skill version' as distinct terms"

requirements-completed: [PROJECT-MD, STATE-ROADMAP-DRIFT]

# Metrics
duration: 2min
completed: 2026-06-02
---

# Phase 27 Plan 03: Canonical PROJECT.md + STATE/ROADMAP Drift Refresh Summary

**Canonical .planning/PROJECT.md created (product identity, versioning policy, split links); STATE.md and ROADMAP.md drift-corrected to reflect Phase 26 merged (PR #60, 46bb394) and Phase 27 current position**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-02T10:29:03Z
- **Completed:** 2026-06-02T10:31:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created `.planning/PROJECT.md` — the canonical product identity document (D-05 minimum-viable): spec-first workflow scaffolder, migration-driven versioning constraint, downstreams named (cparx, callbot, fx-signal-agent), versioning policy (release/baseline tag vs skill version), 3-repo split overview with SPLIT-00/01/02 links, history pointer
- Refreshed `STATE.md`: resolved PROJECT.md pointer (removed "does not yet exist"), updated Progress line to record Phase 26 merged (PR #60, `46bb394`), replaced stale `/gsd-discuss-phase 26` Next action with Phase 27 remaining plans, bumped last_updated timestamp
- Refreshed `ROADMAP.md`: marked v1.20.x milestone as shipped (PR #60 merged `46bb394`), added v1.21.0 stable baseline milestone entry with correct tag-only framing (skill version stays 1.20.0)

## Task Commits

1. **Task 1: Create canonical minimum-viable .planning/PROJECT.md (D-05)** — `f63e8ad` (feat)
2. **Task 2: Refresh STATE.md + ROADMAP.md drift (D-08)** — `9916b76` (chore)

## Files Created/Modified

- `.planning/PROJECT.md` — Created: canonical product identity doc (D-05 minimum-viable); 102 lines; covers what claude-workflow is, core value, who uses it, key constraints, versioning policy, current milestone, 3-repo split overview, history pointer
- `.planning/STATE.md` — Modified: PROJECT.md pointer resolved; Progress line records Phase 26 merge (PR #60, 46bb394); stale Next action replaced; last_updated bumped
- `.planning/ROADMAP.md` — Modified: v1.20.x milestone marked shipped + merged; v1.21.0 milestone entry added with release/baseline tag vs skill version framing

## Decisions Made

- Forward-looking only for PROJECT.md: no phase-by-phase retro, history is a single pointer line to `.planning/phases/` + git log. Keeps the file concise and avoids the bootstrap debt.
- Added a Versioning policy section to PROJECT.md explicitly defining the two-axis model (release/baseline tag vs migration-coupled skill version) — prevents the dual-version appearance from reading as inconsistency in downstream audits and SPLIT-00 gate checks.
- ROADMAP.md got a new v1.21.0 milestone entry (not just marking Phase 26 done) to frame the current in-progress work correctly.

## Deviations from Plan

None — plan executed exactly as written. All acceptance criteria greps passed on first attempt.

## Issues Encountered

None. Documentation-only plan with no runtime dependencies or code symbols.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes. Documentation-only edits. No threat flags.

## Known Stubs

None. PROJECT.md is fully wired with real product identity content; no placeholder text or TODO markers.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- PROJECT.md resolves the SPLIT-00 gate blocker ("PROJECT.md does not yet exist" in STATE.md)
- STATE.md and ROADMAP.md are drift-clean for Phase 27 execution
- Ready for: 27-05 (WR-04 openrouter entry) and 27-06 (CHANGELOG + tag)
- 27-04 already completed (Wave 1 parallel) — SPLIT-01 correction + ADR-0035 + SPLIT-00 pin-by-tag fix

---
*Phase: 27-1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum-*
*Completed: 2026-06-02*
