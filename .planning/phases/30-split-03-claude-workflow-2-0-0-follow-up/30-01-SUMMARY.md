---
phase: 30-split-03-claude-workflow-2-0-0-follow-up
plan: 01
subsystem: migration-engine
tags: [split-03, deletion, tombstone, breaking, observability-extraction]
requires:
  - agenticapps-observability v0.11.1 (live; holds the moved obs tree + ADRs)
provides:
  - claude-workflow with observability tree deleted + 7 informational tombstones
  - migration chain contiguous 1.10.0 -> 1.20.0 (drift anchor = 0021 tombstone)
  - run-tests.sh free of all obs-dependent test bodies
affects:
  - migrations/ (7 sources deleted, 7 tombstones added, run-tests.sh trimmed)
  - docs/decisions/ (6 obs ADRs deleted)
  - add-observability/ (whole tree removed)
  - templates/.claude/scripts/ (3 migrate engines + old-wrappers removed)
tech-stack:
  added: []
  patterns: [informational-tombstone, obs-presence-guard, atomic-deletion-commit]
key-files:
  created:
    - migrations/0012-slash-discovery-moved.md
    - migrations/0013-auto-init-moved.md
    - migrations/0017-add-axiom-logs-destination-moved.md
    - migrations/0018-postphase-observability-hook-moved.md
    - migrations/0019-sentry-crons-and-healthz-moved.md
    - migrations/0020-openrouter-integration-moved.md
    - migrations/0021-with-cron-and-queue-updates-moved.md
  modified:
    - migrations/run-tests.sh
decisions:
  - "0020 IS tombstoned (D-01 / RESEARCH Pitfall 4), overriding RESEARCH §6.1's contradictory 0020-STAYS row"
  - "SKILL.md NOT bumped this wave — stays 1.20.0; 0021 tombstone to_version 1.20.0 keeps drift GREEN; 2.0.0 bump deferred to 30-02"
  - "0011 add-observability scaffolder sanity check removed; fixture uses inline stub SCAN.md (non-hyphenated path matches 0011 requires.verify)"
metrics:
  duration: ~12m
  completed: 2026-06-03
  tasks: 2
  files_changed: 283
  commits: 2
---

# Phase 30 Plan 01: SPLIT-03 Breaking Deletion Wave Summary

Deleted the moved observability tree from claude-workflow, tombstoned the 7 vacated migration slots with verbatim from/to versions, stripped the 8 obs-dependent run-tests.sh bodies, and removed the 6 observability ADRs — all obs-presence-verified against agenticapps-observability v0.11.1 first, leaving the migration chain contiguous and the suite green (PASS 143, FAIL 0) at every commit, with SKILL.md deliberately unbumped at 1.20.0.

## What Was Built

### Task 1 (atomic commit `217baec`)
- Deleted `add-observability/` (tracked tree via `git rm -r`; plus 3577 residual untracked node_modules/build artifacts removed from disk so `! test -d add-observability` holds).
- Deleted 7 moved migration sources (0012, 0013, 0017, 0018, 0019, 0020, 0021) + their 6 fixture dirs (0012/0013/0017/0018/0019/0021 — 0020 has no fixtures).
- Deleted 3 migrate engines (migrate-0017-axiom-destination.sh, migrate-0019-sentry-crons-and-healthz.sh, migrate-0021-with-cron-and-queue-updates.sh) + `migrate-0017-old-wrappers/`.
- Wrote 7 informational `[TOMBSTONE]` `*-moved.md` files (no `## Steps`, `applies_to: []`, verbatim from/to versions).
- Stripped 8 obs-dependent run-tests.sh function bodies + 2 helpers + their dispatcher stanzas; removed the 0011 add-observability scaffolder sanity check and replaced the fixture `cp` with an inline stub `SCAN.md`.

### Task 2 (commit `1229cc9`)
- Deleted 6 observability ADRs (0029-0034); retained ADR-0035 (shared-extraction boundary, not obs, not in obs repo).

## New Test Baseline

| | Before | After |
|---|---|---|
| PASS | 186 | **143** |
| FAIL | 4 | **0** |

The 4 pre-existing FAILs were the `test_migration_0017` fixtures; removing that body dropped FAIL to 0 in the same commit the fixtures were deleted, so the commit boundary is green. The harness prints no `FAIL:` line at FAIL=0; the authoritative green signal is **suite exit 0**. The drift test (`test-skill-md-version-matches-latest-migration-to-version`) PASSes: the alphabetically-last migration is the 0021 tombstone (`to_version: 1.20.0`) == unchanged `skill/SKILL.md version: 1.20.0`.

## Obs-Presence Guard (last-copy safety, STOP-if-absent)

Every moved artifact was confirmed present in `~/Sourcecode/agenticapps/agenticapps-observability/` before `git rm`. No artifact was missing; no deletion was blocked.

| Artifact class | claude-workflow path | obs-repo counterpart | Result |
|---|---|---|---|
| 7 migration .md | migrations/00NN-*.md | migrations/00NN-*.md (0012,0013,0017,0018,0019,0020,0021) | all PRESENT |
| 6 fixture dirs | migrations/test-fixtures/00NN/ | migrations/test-fixtures/00NN/ (0012,0013,0017,0018,0019,0021) | all PRESENT |
| 3 migrate engines | templates/.claude/scripts/migrate-00NN-*.sh | migrations/scripts/migrate-00NN.sh (0017,0019,0021) | all PRESENT (relocated path in obs) |
| old-wrappers dir | templates/.claude/scripts/migrate-0017-old-wrappers/ | migrations/scripts/migrate-0017-old-wrappers | PRESENT |
| 6 ADRs | docs/decisions/0029-0034 | docs/decisions/0029-0034 | all PRESENT |

Note: the obs repo relocated the migrate engines from `templates/.claude/scripts/migrate-00NN-*.sh` to `migrations/scripts/migrate-00NN.sh` during the Phase 29 move (verified via `find`). Counterparts confirmed by content, not by identical relative path.

## Atomicity Confirmation

Task 1's deletions, the 7 tombstone writes, AND the run-tests.sh body removals all landed in ONE commit (`217baec`). The staged set was verified before commit (7 `A`, 1 `M` run-tests.sh, 269 `D`) and the suite was run GREEN (exit 0) prior to committing. The suite was re-confirmed green (exit 0) at the committed HEAD and again after Task 2. No intermediate commit left the suite red.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Residual untracked `add-observability/` content after `git rm -r`**
- **Found during:** Task 1 (verify step)
- **Issue:** `git rm -r add-observability/` removed only tracked files; 3577 untracked files (node_modules, package-lock.json, `.byte-symmetry.snapshot`, vitest results) remained on disk, so the directory physically persisted and `! test -d add-observability` failed. These untracked artifacts are the build-output noise already flagged in STATE.md blockers.
- **Fix:** `rm -rf add-observability` to remove the residual untracked tree from disk after the tracked deletions were staged. Tracked deletions remained staged.
- **Files modified:** add-observability/ (disk removal)
- **Commit:** `217baec`

### Plan verify-string defects (implementation correct; plan assertions overbroad)

The plan's verbatim `<verify>` automated block exits 1 due to two assertion-string defects that do not reflect defects in the implementation. Documented here so the verifier does not misread them as failures:

**2. [Rule 1 - Plan bug] `! grep -q 'scaffolder source missing'` is overbroad**
- The plan assumed this string was unique to the 0011 add-observability sanity check. It also appears in `test_migration_0014` (`$REPO_ROOT/templates/spec-mirrors/11-coding-discipline-0.4.0.md`) and `test_migration_0015` (`$REPO_ROOT/ts-declare-first/SKILL.md`) — both STAYING, non-observability migrations. The 0011 add-observability sanity check (and its `scaffolder_scan` variable) IS removed (confirmed: `grep scaffolder_scan run-tests.sh` returns nothing; only the inline-stub printf references the path). Deleting the 0014/0015 guards would break staying tests, so they were correctly left intact.

**3. [Rule 1 - Plan bug] `bash run-tests.sh | tail -4 | grep -q 'FAIL: 0'` can never match this harness**
- The harness Summary only prints a `FAIL:` line when `FAIL > 0` (run-tests.sh: `[ $FAIL -gt 0 ] && echo ... FAIL`). At FAIL=0 there is no `FAIL: 0` line. The real green signal is suite **exit 0**, which holds. A corrected, comprehensive verify (24 conditions, green = exit 0) passes with PASS=24 FAILED=0.

**4. [Note] Acceptance-criterion `test -d migrations/test-fixtures/0016` is incorrect**
- 0016 has no own fixture dir — its behavior is exercised by fixtures under `test-fixtures/0005` (per run-tests.sh comment). `test_migration_0016()` exists and runs. The plan's `<verify>` automated block does not check 0016; only one prose acceptance line does, and it is factually wrong about 0016 having a fixture dir. No action needed.

## Self-Check: PASSED

- Tombstone files: all 7 FOUND.
- Commits: `217baec` and `1229cc9` both FOUND in git log.
- Deletions: add-observability/ GONE; 7 originals + fixtures + 3 engines + old-wrappers GONE; 6 ADRs GONE; ADR-0035 retained.
- Suite: exit 0 (PASS 143, FAIL 0) at committed HEAD; drift PASS; SKILL.md still 1.20.0.
