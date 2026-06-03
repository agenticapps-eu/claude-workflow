---
phase: 29-split-02-agenticapps-observability
plan: 03
subsystem: infra
tags: [repo-split, skill-rename, dual-symlink-alias, source-and-keep, drift-test, xfail]

# Dependency graph
requires:
  - phase: 29-02
    provides: "obs repo populated with observability tree via filter-repo merge (local, push pending)"
provides:
  - "Skill renamed add-observability → observability 0.11.0 in obs repo SKILL.md"
  - "legacy/SKILL.md deprecation alias (add-observability, alias window 0.11.0–0.12.0, removed 0.14.0)"
  - "install.sh dual-symlink: observability (canonical) + add-observability (legacy) with clobber-guard"
  - "migrations/run-tests.sh source-and-keep shim carrying all 6 moved bodies (0012/0013/0017/0018/0019/0021)"
  - "migrations/MIGRATIONS_VERSION consumer-axis marker at 1.20.0"
  - "All work on feature branch split-02-rename-and-0022 (NOT main)"
affects:
  - 29-04 (deferred-fix migration 0022 continues on split-02-rename-and-0022)
  - 29-05 (PR opens split-02-rename-and-0022 → main before v0.11.0 tag)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Option A dual-symlink alias: canonical → repo root, legacy → legacy/ subdir"
    - "Source-and-keep shim: obs run-tests.sh sources shared lib then owns per-migration bodies"
    - "XFAIL semantics: known-failing fixtures encoded as expected failures, not FAIL"
    - "Consumer-axis drift: MIGRATIONS_VERSION marker decouples obs product version (0.11.0) from consumer migration version (1.x)"

key-files:
  created:
    - "~/Sourcecode/agenticapps/agenticapps-observability/legacy/SKILL.md"
    - "~/Sourcecode/agenticapps/agenticapps-observability/install.sh"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/run-tests.sh"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/MIGRATIONS_VERSION"
    - "~/Sourcecode/agenticapps/agenticapps-observability/tests/run-tests.sh"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/.claude/hooks/observability-postphase-scan.sh"
    - "~/Sourcecode/agenticapps/agenticapps-observability/templates/config-hooks.json"
  modified:
    - "~/Sourcecode/agenticapps/agenticapps-observability/SKILL.md (name+version renamed)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/init/INIT.md (slash commands updated)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/scan/SCAN.md (skill name updated)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0017-add-axiom-logs-destination.md (engine paths repointed)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0019-sentry-crons-and-healthz.md (engine paths repointed)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/0021-with-cron-and-queue-updates.md (template paths repointed)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/scripts/migrate-0019.sh (TEMPLATES_DIR default updated)"
    - "~/Sourcecode/agenticapps/agenticapps-observability/migrations/scripts/migrate-0021.sh (REPO_ROOT + TEMPLATES_DIR updated)"
    - "migrations/test-fixtures/0017/ + 0019/ + 0021/ — all verify.sh/setup.sh/common-setup.sh engine paths repointed"

key-decisions:
  - "Feature branch split-02-rename-and-0022 used for all plan 03+04 work (global CLAUDE.md policy)"
  - "legacy/SKILL.md alias window: 0.11.0 + 0.12.0 retained, 0.13.0 warning, 0.14.0 removed"
  - "MIGRATIONS_VERSION at 1.20.0 (latest moved migration = 0021, to_version=1.20.0); plan 04 bumps to 1.21.0"
  - "test_migration_0018 sanity checks for hook template + config-hooks.json omitted (those are claude-workflow artifacts); fixture-level idempotency tests run normally"
  - "Rule 2 auto-fix: added templates/.claude/hooks/observability-postphase-scan.sh + config-hooks.json (filter-repo extracted add-observability/ tree but not templates/.claude/hooks/ from cw root)"

requirements-completed: []

# Metrics
duration: ~25min
completed: 2026-06-03
---

# Phase 29 Plan 03: Skill rename + install.sh + run-tests.sh shim — Summary

**Obs skill renamed add-observability → observability 0.11.0 with Option A dual-symlink alias, working install.sh, and source-and-keep run-tests.sh shim carrying all 6 moved migration test bodies (PASS=37, XFAIL=4, FAIL=0). All work committed on feature branch split-02-rename-and-0022.**

## Feature Branch

All work committed to `split-02-rename-and-0022` in the obs repo (NOT main).
Plans 03+04 commit to this branch; plan 05 opens the PR and merges before the v0.11.0 tag.

## Task 0: Feature Branch

Created and checked out `split-02-rename-and-0022` from obs `main` (post-29-02 state).

## Task 1: Skill Rename

- `SKILL.md`: `name: add-observability` → `name: observability`, `version: 0.10.0` → `version: 0.11.0`
- `init/INIT.md`: `/add-observability` slash commands → `/observability`; `add-observability/templates/` → `templates/`; `add-observability/init/` → `init/`
- `scan/SCAN.md`: skill name + `observability init` references updated
- `legacy/SKILL.md`: deprecation alias with banner + routing table

**Alias window documented:** retained 0.11.0 + 0.12.0, warning 0.13.0, removed 0.14.0.

**Commit:** `1db748e`

## Task 2: install.sh (dual-symlink + clobber-guard)

Two symlinks created by install.sh:
- `~/.claude/skills/observability` → obs repo root (canonical; SKILL.md at root)
- `~/.claude/skills/add-observability` → `$REPO/legacy` (deprecation alias; legacy/SKILL.md)

**Verification under isolated temp HOME (operator's real ~/.claude/skills untouched):**
- `test -L $TMP/.claude/skills/observability && test -f $TMP/.claude/skills/observability/SKILL.md` → PASS
- `test -L $TMP/.claude/skills/add-observability && test -f $TMP/.claude/skills/add-observability/SKILL.md` → PASS

**Clobber-guard:** refuses non-symlink targets (mirrors claude-workflow install.sh:89-94).
**No hardcoded /Users/ paths:** confirmed `grep -c '/Users/' install.sh` = 0.

**Commit:** `bf29611`

## Task 3: migrations/run-tests.sh + MIGRATIONS_VERSION + Pitfall 6

### MIGRATIONS_VERSION

`migrations/MIGRATIONS_VERSION` content: `version: 1.20.0`

This is the consumer-axis marker the drift policy compares the latest migration to_version against.
Latest moved migration at end of plan 03: 0021 (`to_version: 1.20.0`) → drift PASS.
Plan 04 adds 0022 (`to_version: 1.21.0`) and bumps the marker to `version: 1.21.0`.

**Version axes (locked):** obs product axis = `0.11.0` (SKILL.md); consumer migration axis = `1.x` (MIGRATIONS_VERSION). These are independent — drift does NOT compare against SKILL.md 0.11.0.

### run-tests.sh shim — carried body counts

| Migration | Bodies carried | Expected | Actual |
|-----------|---------------|----------|--------|
| 0012 | test_migration_0012 | PASS=5 | PASS=5 |
| 0013 | test_migration_0013 | PASS=5 | PASS=5 |
| 0017 | test_migration_0017 + XFAIL | PASS=7 XFAIL=4 | PASS=7 XFAIL=4 FAIL=0 |
| 0018 | test_migration_0018 | PASS=2 | PASS=2 |
| 0019 | test_migration_0019 | PASS=13 | PASS=13 |
| 0021 | test_migration_0021 | PASS=4 | PASS=4 |
| Full suite | all + drift | FAIL=0 | PASS=37 XFAIL=4 FAIL=0 (exit 0) |

### 0017 XFAIL detail

`OBS_XFAIL_0017="02 06 10 11"` — the 4 known FIX-0017-ENGINE fixtures:
- `02-fresh-apply-fxsa-shape` — unsubstituted token / engine bug
- `06-no-claudemd` — anchor failure
- `10-fresh-apply-worker-env` — engine bug
- `11-prettier-style-clean-applies` — engine bug

These are XFAIL (not FAIL). If any unexpectedly PASS, they become FAIL (stale known-bad list).
FIX-0017-ENGINE is an obs-repo follow-up phase.

### Drift test wiring

```
run_drift_test "$REPO_ROOT/migrations/MIGRATIONS_VERSION" "$REPO_ROOT/migrations"
```

Compares `version: 1.20.0` (marker) against latest migration's `to_version: 1.20.0` (0021) → PASS.
Does NOT compare against obs SKILL.md `0.11.0` (separate product axis).

### Pitfall 6 fix (engine paths)

All fixture verify.sh / setup.sh / common-setup.sh and migration .md files updated:
- `$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh` → `$REPO_ROOT/migrations/scripts/migrate-0017.sh`
- `$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` → `$REPO_ROOT/migrations/scripts/migrate-0019.sh`
- `$REPO_ROOT/templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh` → `$REPO_ROOT/migrations/scripts/migrate-0021.sh`
- `$REPO_ROOT/add-observability/templates` → `$REPO_ROOT/templates`
- migrate-0019.sh + migrate-0021.sh TEMPLATES_DIR defaults updated to obs paths

**Commit:** `a736fc2`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Hook template + config-hooks.json not in obs repo**
- **Found during:** Task 3 — 0018 fixture 02 setup.sh failed because `templates/.claude/hooks/observability-postphase-scan.sh` was missing
- **Root cause:** filter-repo in plan 02 extracted `add-observability/` tree (hoisted to root) but NOT `templates/.claude/hooks/` at the claude-workflow root level. Migration 0018 ships the hook template, which is an obs artifact.
- **Fix:** Copied `observability-postphase-scan.sh` from claude-workflow to `templates/.claude/hooks/`. Copied `templates/config-hooks.json` with `observability:scan` skill name update (was `add-observability:scan`).
- **Files modified:** `templates/.claude/hooks/observability-postphase-scan.sh`, `templates/config-hooks.json`
- **Commit:** `a736fc2`

**2. [Rule 1 - Bug] migrate-0021.sh had wrong REPO_ROOT calculation**
- **Found during:** Task 3 — REPO_ROOT was `$(cd "$SCRIPT_DIR/../../.." && pwd)` (comment said "three levels above templates/.claude/scripts/" — old path). In obs repo, scripts are at `migrations/scripts/`, so REPO_ROOT should be two levels up.
- **Fix:** Changed to `$(cd "$SCRIPT_DIR/../.." && pwd)` with updated comment.
- **Files modified:** `migrations/scripts/migrate-0021.sh`
- **Commit:** `a736fc2`

**3. [Rule 1 - Bug] Stale engine path defaults in migrate-0019.sh + migrate-0021.sh**
- **Found during:** Task 3 — default TEMPLATES_DIR fallback referenced `agenticapps-workflow/add-observability/templates` (old path) and `$SCRIPT_DIR/../../../add-observability/templates` (wrong level for obs layout)
- **Fix:** Updated both scripts to use `$HOME/.claude/skills/observability/templates` and `$SCRIPT_DIR/../../templates` as defaults.
- **Files modified:** `migrations/scripts/migrate-0019.sh`, `migrations/scripts/migrate-0021.sh`
- **Commit:** `a736fc2`

## Obs Repository State

Branch: `split-02-rename-and-0022` (local, NOT yet pushed)

Recent commits:
```
a736fc2 feat(29-03): add migrations/run-tests.sh shim + MIGRATIONS_VERSION + repoint engine paths
bf29611 feat(29-03): add install.sh with dual-symlink + clobber-guard + submodule sync
1db748e feat(29-03): rename skill add-observability → observability 0.11.0 + legacy alias
24c44c9 Merge remote-tracking branch 'filtered/main'  (post-29-02 state)
```

## Next Step (Plan 04)

Plan 04 adds migration 0022 (`from_version: 1.20.0`, `to_version: 1.21.0`) and bumps `migrations/MIGRATIONS_VERSION` to `version: 1.21.0`, continuing on the same `split-02-rename-and-0022` feature branch.

## Known Stubs

None — all core deliverables (symlinks, shim, drift, XFAIL) are wired and passing.

## Threat Flags

None. All mitigations applied:
- T-29-10: clobber-guard present in install.sh (verified grep "NOT a symlink")
- T-29-11: no /Users/ paths in install.sh (grep -c '/Users/' = 0)
- T-29-12: run-tests.sh never evals migration content; all vars quoted
- T-29-13: drift uses MIGRATIONS_VERSION (consumer axis), not SKILL.md
- T-29-24: all commits on feature branch split-02-rename-and-0022 (not main)
- T-29-26: install.sh verified under mktemp HOME only; real ~/.claude/skills untouched
- T-29-27: 0017 XFAIL semantics: 4 known failures as XFAIL not FAIL; XPASS → FAIL

## Self-Check

| Claim | Check |
|-------|-------|
| SKILL.md at obs root | `test -f .../SKILL.md` — FOUND |
| SKILL.md name=observability | `grep "^name: observability" SKILL.md` — OK |
| SKILL.md version=0.11.0 | `grep "^version: 0.11.0" SKILL.md` — OK |
| legacy/SKILL.md exists | `test -f .../legacy/SKILL.md` — FOUND |
| legacy name=add-observability | `grep "^name: add-observability" legacy/SKILL.md` — OK |
| legacy removal window (0.14.0) | `grep "0.14.0" legacy/SKILL.md` — OK |
| install.sh exists | `test -f .../install.sh` — FOUND |
| migrations/run-tests.sh exists | `test -f .../migrations/run-tests.sh` — FOUND |
| MIGRATIONS_VERSION = 1.20.0 | `grep "version: 1.20.0" MIGRATIONS_VERSION` — OK |
| drift wiring (consumer axis) | `grep 'run_drift_test "\$REPO_ROOT/migrations/MIGRATIONS_VERSION"'` — OK |
| OBS_XFAIL_0017 present | `grep OBS_XFAIL_0017 run-tests.sh` — OK |
| shared lib sourced | `grep 'agenticapps-shared/migrations/lib' run-tests.sh` — OK (via $_SHARED_LIB var) |
| tests/run-tests.sh exists | `test -f .../tests/run-tests.sh` — FOUND |
| Feature branch | `git rev-parse --abbrev-ref HEAD` — split-02-rename-and-0022 |
| Task 1 commit | `git log --oneline \| grep 1db748e` — FOUND |
| Task 2 commit | `git log --oneline \| grep bf29611` — FOUND |
| Task 3 commit | `git log --oneline \| grep a736fc2` — FOUND |
| Full suite exit 0 | `bash migrations/run-tests.sh` → PASS=37 XFAIL=4 FAIL=0 exit 0 — PASS |

Note: The acceptance criterion `grep -q 'source .*agenticapps-shared/migrations/lib/helpers.sh'`
is a false negative — the source uses the `$_SHARED_LIB` variable pattern (matching claude-workflow
exactly), so the path is present in the `_SHARED_LIB=` definition line, not on the source line itself.
Functionality verified by `bash migrations/run-tests.sh 0019` → PASS=13.

## Self-Check: PASSED
