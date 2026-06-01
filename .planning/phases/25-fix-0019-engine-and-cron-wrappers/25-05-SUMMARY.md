---
phase: 25
plan: 05
subsystem: migration-engine
tags: [migration-0021, queue-monitor, cron-monitor, re-rev, dirty-detection, version-bump]
dependency_graph:
  requires: [25-01, 25-02, 25-03, 25-04]
  provides: [migration-0021-engine, v1.20.0-delivery, SC5-typecheck-fixture]
  affects: [skill/SKILL.md, add-observability/SKILL.md, CHANGELOG.md, templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh]
tech_stack:
  added: []
  patterns: [canonicalize_awk-mirror-not-fork, twofold-idempotency-M-8, dirty-detection-M-9, paths-mapping-bundler-moduleResolution, frozen-baselines-M-1]
key_files:
  created:
    - templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh
    - .planning/phases/25-fix-0019-engine-and-cron-wrappers/25-05-SUMMARY.md
  modified:
    - migrations/0021-with-cron-and-queue-updates.md
    - migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/tsconfig.json
    - migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts
    - skill/SKILL.md
    - add-observability/SKILL.md
    - CHANGELOG.md
    - add-observability/CHANGELOG.md
    - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
    - migrations/0019-sentry-crons-and-healthz.md
decisions:
  - Migration 0021 uses paths mapping in tsconfig for @sentry/cloudflare — moduleResolution:bundler requires paths; ambient module decl alone is insufficient for external package resolution
  - from_version/to_version in migration spec must be unquoted to satisfy the grep+awk version drift test (F4)
  - Engine BASELINES_DIR points to migrations/test-fixtures/0021/baselines/v1.19.0 (frozen literals per codex M-1)
metrics:
  duration: ~60 minutes (resumed from compacted session)
  completed: 2026-05-31T19:29:17Z
  tasks_completed: 7
  files_changed: 10
---

# Phase 25 Plan 05: Migration 0021 Engine + Version Bumps Summary

**One-liner:** Migration 0021 re-rev engine with dirty detection + twofold idempotency (mirrors 0019 canonicalize_awk); ships queue-monitor.ts and updated cron-monitor.ts to v1.19.0 projects; bumps skill/SKILL.md 1.19.0→1.20.0 and add-observability/SKILL.md 0.8.0→0.9.0.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 5.1 | Migration 0019 engine D-11 (queue-monitor.ts for cf-worker+pages) | f63cd79 | migrate-0019-sentry-crons-and-healthz.sh |
| 5.2 | Migration 0019 spec doc update | a9a2be5 | migrations/0019-sentry-crons-and-healthz.md |
| 5.3 | Migration 0021 spec doc | 3e2a8ae | migrations/0021-with-cron-and-queue-updates.md |
| 5.4+5.5 | Migration 0021 engine + fixtures GREEN | fb6d841 | migrate-0021-with-cron-and-queue-updates.sh, fixtures/0021/04/* |
| 5.6 | Version bumps + CHANGELOG entries | 57efaa9 | skill/SKILL.md, add-observability/SKILL.md, CHANGELOG.md, add-observability/CHANGELOG.md |
| 5.7 | Full suite verification + to_version fix | 6984810 | migrations/0021-with-cron-and-queue-updates.md |

## Verification Results

- Migration 0021 fixtures: 4/4 PASS (01-fresh-apply, 02-dirty-refuse, 03-idempotent-skip, 04-SC5-strict-typecheck)
- Full migration suite: 189 PASS, 0 FAIL
- Template test suite: all stacks PASS

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] tsconfig moduleResolution:bundler requires paths for @sentry/cloudflare**
- **Found during:** Task 5.5 fixture 04 runtime verification
- **Issue:** `moduleResolution: "bundler"` resolves external packages via node_modules only; `declare module "@sentry/cloudflare"` in `types.d.ts` (listed in `include`) is not consulted. Error: `Cannot find module '@sentry/cloudflare'`.
- **Fix:** Added `"paths": { "@sentry/cloudflare": ["./types.d.ts"] }` to fixture tsconfig.json.
- **Files modified:** `migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/tsconfig.json`
- **Commit:** fb6d841

**2. [Rule 1 - Bug] to_version quoted in migration frontmatter breaks F4 version drift test**
- **Found during:** Task 5.7 full suite run
- **Issue:** `to_version: "1.20.0"` (YAML quoted string) causes `grep ^to_version: | awk '{print $2}'` to return `"1.20.0"` (with quotes), which does not equal skill version `1.20.0`. All other migration specs use unquoted values.
- **Fix:** Changed `from_version: "1.19.0"` / `to_version: "1.20.0"` to unquoted form (matching 0019 pattern).
- **Files modified:** `migrations/0021-with-cron-and-queue-updates.md`
- **Commit:** 6984810

**3. [Rule 1 - Bug] wrapper/index.ts template tokens broke tsconfig include glob**
- **Found during:** Task 5.5 first tsc run
- **Issue:** The fixture 04 tsconfig originally had `"include": ["./wrapper/**/*.ts"]` which pulled in `wrapper/index.ts` (seeded from lib-observability.ts template); that file contains `{{DEBUG_SAMPLE_RATE}}` etc. unsubstituted tokens causing parse errors.
- **Fix:** Changed include to explicit file list: `types.d.ts, env.ts, smoke.ts, wrapper/cron-monitor.ts, wrapper/queue-monitor.ts`. Added exclude list for template files.
- **Files modified:** `migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/tsconfig.json`
- **Commit:** fb6d841 (folded with engine commit)

## Known Stubs

None — all template files are fully wired. Migration engine applies real v1.20.0 templates from `add-observability/templates/`.

## Threat Flags

None — this plan introduces no new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries. The migration engine script runs in user's local environment with the same file permissions as the project.

## Self-Check: PASSED

All key files verified present. All task commits verified in git log. Version bumps confirmed (skill/SKILL.md: 1.20.0, add-observability/SKILL.md: 0.9.0). Full migration suite: 189 PASS, 0 FAIL.
