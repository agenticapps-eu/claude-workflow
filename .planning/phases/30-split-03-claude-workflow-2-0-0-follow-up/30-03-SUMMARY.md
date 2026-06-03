---
phase: 30-split-03-claude-workflow-2-0-0-follow-up
plan: 03
subsystem: infra
tags: [observability, split, migration, install.sh, changelog, upgrade-docs, 2.0.0]

# Dependency graph
requires:
  - phase: 30-01
    provides: add-observability/ tree deleted, 7 tombstones, 6 obs ADRs deleted
  - phase: 30-02
    provides: migration 0022 (repoint + to_version 2.0.0 + #58 hook), SKILL.md 2.0.0, drift PASS
provides:
  - install.sh add-observability skill-pair DROPPED (no dangling symlink target)
  - forward-looking refs repointed add-observability -> observability (slash cmds -> /observability)
  - templates/config-hooks.json skill repointed to observability:scan
  - docs/UPGRADING.md (1.21.0 -> 2.0.0 upgrade story, supported floor 1.21.0)
  - CHANGELOG [2.0.0] breaking-change section
  - README link to docs/UPGRADING.md
affects: [30-03 Task 3 ship gate, downstream factiv consumers upgrading to 2.0.0]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Skill-pair DROP (not rename) when a scaffolder subdir is removed: delete the LINKS entry + help echo + grep-hint alternation, then assert remaining pairs' subdirs exist"
    - "Forward-looking templates ship canonical names (/observability), not legacy aliases (D-03 forked-axis world)"
    - "Reference cleanup scoped to non-immutable forward-looking files only; immutable migrations keep old-name refs resolved by the obs add-observability alias"

key-files:
  created:
    - docs/UPGRADING.md
  modified:
    - install.sh
    - README.md
    - setup/SKILL.md
    - templates/config-hooks.json
    - templates/.claude/hooks/observability-postphase-scan.sh
    - templates/.claude/claude-md/workflow.md
    - CHANGELOG.md

key-decisions:
  - "D-06 named-target override: obs repo has no docs/INSTALLATION.md (RESEARCH §7); UPGRADING.md cross-references the obs README + install.sh instead — deliberate, correct override"
  - "install.sh add-observability pair DROPPED entirely, not renamed: no observability/ subdir exists in this repo (obs moved to sibling repo, installs separately)"
  - "UPGRADING.md prose avoids the literal string 'INSTALLATION.md' to satisfy the acceptance grep while still documenting the absence of a standalone install doc"

patterns-established:
  - "Skill-pair drop hardening: assert every remaining LINKS pair's source subdir exists after editing install.sh so the loop never targets a missing dir (T-30-14 mitigation)"

requirements-completed: [D-04, D-05, D-06]

# Metrics
duration: ~20min
completed: 2026-06-03
---

# Phase 30 Plan 03: SPLIT-03 reference cleanup + upgrade story Summary

**Dropped the add-observability skill-pair from install.sh, repointed all forward-looking refs to the canonical `observability` skill (`/observability` slash commands + config-hooks.json `observability:scan`), and wrote the 1.21.0 -> 2.0.0 upgrade story (docs/UPGRADING.md + CHANGELOG [2.0.0]). Task 3 (ship gate) is left pending the orchestrator checkpoint.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-06-03 (sequential executor on plan-30-split-03)
- **Completed:** 2026-06-03
- **Tasks:** 2 of 3 (Task 3 = checkpoint:human-verify, owned by orchestrator)
- **Files modified:** 7 (6 modified + 1 created)

## Accomplishments

- **install.sh skill-pair DROP (not rename):** removed the `"add-observability add-observability"` LINKS entry, the `/add-observability` help echo, the `|add-observability` discovery grep-hint alternation, and the header-comment mention. Asserted every remaining LINKS pair's source subdir (`skill`, `setup`, `update`) still exists — no dangling symlink target. `bash -n install.sh` passes.
- **Forward-looking refs repointed** in the 5 other non-immutable files: README.md (install tree + three-skills claim + UPGRADING link), setup/SKILL.md (skill renamed, now separate install), templates/config-hooks.json (`observability:scan`), templates/.claude/hooks/observability-postphase-scan.sh (`/observability` slash invocations + prose), templates/.claude/claude-md/workflow.md (`/observability scan-apply`).
- **docs/UPGRADING.md** (75 lines): 1.21.0 -> 2.0.0 transition, supported upgrade floor (1.21.0, Phase 27 SPLIT-00 baseline; pre-baseline <1.21.0 replay out of scope), why-breaking, what-changed (tombstones + 0022), separate obs install with exact commands, alias-retention note, how-to-upgrade.
- **CHANGELOG [2.0.0]** section added at the top (breaking obs extraction, install.sh skill-pair drop, tombstones, migration 0022, #58 deterministic Phase Sentinel hook); older entries untouched.
- **Suite stayed green** after every task: exit 0, PASS 149, drift test (`test-skill-md-version-matches-latest-migration-to-version`) PASS at 2.0.0.

## Task Commits

1. **Task 1: Drop add-observability skill-pair from install.sh + repoint 5 other forward-looking files** - `13258c3` (chore)
2. **Task 2: docs/UPGRADING.md + CHANGELOG [2.0.0] + README link** - `8a7dccd` (docs)

_Note: the README link to docs/UPGRADING.md was committed in Task 1 (alongside the other README edits), not Task 2._

## Files Created/Modified

- `install.sh` - dropped the add-observability skill-pair (LINKS entry + help echo + grep-hint alternation + header comment); remaining 3 pairs verified to have existing subdirs
- `README.md` - removed observability from the install tree + skills-count claim; added a link to docs/UPGRADING.md and a note that observability installs separately
- `setup/SKILL.md` - renamed the related-skill reference to `observability`; documents it as a separate install
- `templates/config-hooks.json` - `"skill": "add-observability:scan"` -> `"skill": "observability:scan"` (line 97); JSON validated with jq
- `templates/.claude/hooks/observability-postphase-scan.sh` - `/add-observability` -> `/observability` slash invocations + skill-name prose in header comments; behaviour unchanged (advisory, exit 0)
- `templates/.claude/claude-md/workflow.md` - `/add-observability scan-apply` -> `/observability scan-apply`
- `docs/UPGRADING.md` - NEW; the 1.21.0 -> 2.0.0 upgrade story with the supported floor + obs-repo cross-reference
- `CHANGELOG.md` - NEW `## [2.0.0]` section at top; historical entries unchanged

## Decisions Made

- **D-06 named-target override:** D-06 named the obs repo's `docs/INSTALLATION.md` as the cross-reference target, but RESEARCH §7 confirmed that file does not exist in the obs repo. UPGRADING.md cross-references the obs README + install.sh instead. This is a deliberate, correct override of D-06's named target.
- **install.sh DROP, not rename:** there is no `observability/` subdir in this repo (the obs skill moved to the sibling repo and installs separately per D-03), so renaming the LINKS pair to `observability` would create a dangling symlink target. The pair was removed entirely.
- **UPGRADING.md wording:** the prose deliberately avoids the literal string `INSTALLATION.md` so the acceptance grep (`! grep -q 'INSTALLATION.md'`) passes, while still documenting that no standalone install doc exists in the obs repo.

## Deviations from Plan

None - plan executed exactly as written. (The README -> UPGRADING.md link was naturally folded into the Task 1 README edits rather than Task 2, but the link is present and committed; no behavioural deviation.)

## Issues Encountered

- The Task 2 verify block's `! grep -q 'INSTALLATION.md' docs/UPGRADING.md` initially failed because the draft prose said "There is no separate `INSTALLATION.md`...". Reworded to "there is no separate standalone install doc to cross-reference" — verify block now returns OK.
- `git add` for the tracked template files under `templates/.claude/` tripped the `.gitignore` advisory; the files are already tracked, so `git add -f` staged them correctly (no new ignored content added).

## Known Stubs

None.

## Task 3 — PENDING (orchestrator checkpoint)

Task 3 (`checkpoint:human-verify`, gate=blocking) — **ship 2.0.0** — was intentionally NOT executed by this executor. Per the objective, the orchestrator owns the ship gate: run the full suite + `/gsd-review` on the phase diff, then gate the breaking PR / `v2.0.0` tag / merge on explicit human approval. The CHANGELOG [2.0.0] section, SKILL.md 2.0.0 (from 30-02), docs/UPGRADING.md, and the reference cleanup are all in place; suite is green and drift PASSes at 2.0.0, so the ship gate's automated precondition is satisfied.

## Next Phase Readiness

- All forward-looking files reference `observability`; install.sh ships no observability skill-pair; immutable migrations + .planning + CHANGELOG history untouched.
- Ready for Task 3 ship gate: orchestrator runs suite + /gsd-review, then opens the breaking PR (`v2.0.0 chore!: extract observability to agenticapps-observability (SPLIT-03)`), creates the `v2.0.0` tag, and merges on human approval.

## Self-Check: PASSED

- FOUND: docs/UPGRADING.md
- FOUND: .planning/phases/30-split-03-claude-workflow-2-0-0-follow-up/30-03-SUMMARY.md
- FOUND commit: 13258c3 (Task 1)
- FOUND commit: 8a7dccd (Task 2)

---
*Phase: 30-split-03-claude-workflow-2-0-0-follow-up*
*Completed: 2026-06-03 (Tasks 1-2; Task 3 pending orchestrator checkpoint)*
