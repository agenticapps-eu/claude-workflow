---
phase: 25
plan: "02"
subsystem: templates/.claude/scripts
tags:
  - wave-1
  - engine-fix
  - d-01
  - codex-m2
  - codex-m3
  - index-ts-anchor
  - partial-green

dependency_graph:
  requires:
    - "25-01 (ADR-0031 + RED fixtures 08/09/11/12)"
  provides:
    - "D-01 engine anchor: index.ts accepted as canonical materialised filename for cf-worker + cf-pages"
    - "Codex M-2 dist-path negative filter: index.ts under dist/build/out dropped even with sibling co-anchor"
    - "Codex M-3 refuse-path: DIRTY index.ts projects emit patch referring to index.ts (not lib-observability.ts)"
    - "resolve_anchor_files() helper: picks actually-present anchor at fingerprint time"
    - "Fixtures 11 + 12 GREEN (T-25-01 + T-25-04 mitigated)"
    - "Fixtures 08 + 09 partial-GREEN (cron-monitor + healthz + version bump; queue-monitor deferred to Plan 05)"
  affects:
    - "Plan 05 (D-11 apply_root expansion — queue-monitor.ts copy step completes 08/09 full GREEN)"

tech_stack:
  added: []
  patterns:
    - "Pre-classify pipe filter: function defined before ROOTS=(), called via | pipe in find subshell"
    - "resolve_anchor_files: picks actually-present anchor (index.ts > lib-observability.ts) per stack"
    - "_template_name_for_anchor: maps project-side index.ts to template-side lib-observability.ts for hash comparison"
    - "Canonicaliser unchanged: both index.ts and lib-observability.ts produce identical canonical hash (content is identical)"

key_files:
  created: []
  modified:
    - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh

decisions:
  - "Helper placement: _filter_index_ts_requires_co_anchor defined at line 208 (before ROOTS=() at 235) — function must precede the find pipeline that calls it via pipe"
  - "Two-filter approach: (a) sibling co-anchor check drops bare index.ts; (b) dist/build/out path check drops compiled output even with co-anchor (codex M-2)"
  - "resolve_anchor_files preferred over extending stack_fingerprint_files: returns the actually-present file, not a static list — is_known_clean_wrapper can then use consistent $dir/$f path"
  - "_template_name_for_anchor as a small helper: both is_known_clean_wrapper and emit_refuse_artifacts need the same mapping; helper avoids duplication"
  - "emit_refuse_artifacts_for patch header: added '# Anchor file:' annotation showing canonical vs legacy anchor for operator clarity (codex M-3)"

metrics:
  duration_minutes: 25
  completed_date: "2026-05-31"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 1
---

# Phase 25 Plan 02: Engine fix (D-01) — index.ts anchor for cf-worker/cf-pages Summary

**One-liner:** 0019 engine extended with `_filter_index_ts_requires_co_anchor` pre-classify filter + `resolve_anchor_files` fingerprint helper + `_template_name_for_anchor` mapping, enabling index.ts-anchored cf-worker/cf-pages wrappers to be discovered, classified CLEAN, and migrated (fixtures 08/09 partial-GREEN; 11/12 GREEN; all existing 01-07 still pass).

## Tasks Completed

| Task | Name | Commit | Key Deliverables |
|------|------|--------|------------------|
| 2.1 | Engine — extend find candidates + pre-classify filter + classify_stack | 38c9bdf | `_filter_index_ts_requires_co_anchor` at line 208; `-name index.ts` in find at line 267; updated classify_stack at lines 351-380 |
| 2.2 | Engine — resolve_anchor_files helper + fingerprint refactor + refuse-path rewire | 38c9bdf | `resolve_anchor_files` at line 409; `_template_name_for_anchor` at line 452; `is_known_clean_wrapper` rewired at line 587; `emit_refuse_artifacts` diff loop rewired at line 743; `emit_refuse_artifacts_for` patch header at line 672 |

Note: Tasks 2.1 and 2.2 were committed together because `is_known_clean_wrapper` (Task 2.2) must be rewired before fixtures 08/09 can pass the fingerprint check — Task 2.1 alone would leave them in DIRTY/REFUSE state. A single atomic commit captures the complete, consistent state.

## Engine Lines Actually Edited (Post-Edit Reality)

| Section | Lines | Change |
|---------|-------|--------|
| `_filter_index_ts_requires_co_anchor` helper | 197–233 (definition) | NEW — placed before `ROOTS=()` at line 235 |
| `find` candidate set | 261–275 | Added `-name index.ts` + `| _filter_index_ts_requires_co_anchor` pipe |
| `classify_stack` cf-pages canonical case | 349–357 | Added `{ [ -f "$dir/index.ts" ] || [ -f "$dir/lib-observability.ts" ]; }` |
| `classify_stack` cf-pages anchor check | 360–364 | Same dual-anchor condition |
| `classify_stack` cf-worker | 374–379 | Same dual-anchor condition |
| `resolve_anchor_files` helper | 396–450 | NEW — placed after `stack_fingerprint_files` |
| `_template_name_for_anchor` helper | 452–465 | NEW — maps project-side `index.ts` to template-side `lib-observability.ts` |
| `is_known_clean_wrapper` | 585–602 | Rewired to `resolve_anchor_files` + `_template_name_for_anchor` |
| `emit_refuse_artifacts_for` | 660–732 | Added anchor resolution + `# Anchor file:` patch header annotation |
| `emit_refuse_artifacts` diff loop | 742–752 | Rewired to `resolve_anchor_files` + `_template_name_for_anchor` |

## Filter Implementation Notes

`_filter_index_ts_requires_co_anchor` is implemented as a pipe filter (stdin → stdout), called via `| _filter_index_ts_requires_co_anchor` between `find ... -print` and `| sort -u` in the ROOTS collection loop. This is consistent with the existing `_filter_supabase_edge_roots` pattern.

Critical placement requirement: the function must be defined BEFORE the find subshell that pipes through it. Initial draft placed it after — causing `_filter_index_ts_requires_co_anchor: command not found` error that reverted all 10 previously-passing fixtures to FAIL. Fixed by moving the definition to line 208 (before `ROOTS=()` at line 235).

## Fixture Results

| Fixture | Status | Notes |
|---------|--------|-------|
| 01–07, 07-react-vite-only | PASS | No regression — existing fixtures unchanged |
| 08-index-ts-anchored-worker | PARTIAL-GREEN | cron-monitor.ts + healthz-snippet.ts + version 1.18.0 OK; queue-monitor.ts deferred to Plan 05 D-11 |
| 09-index-ts-anchored-pages | PARTIAL-GREEN | Same as 08 |
| 11-stray-index-ts-no-co-anchor | PASS | Pre-classify filter drops both stray index.ts files |
| 12-dist-shaped-anchor-pair | PASS | dist-path filter drops dist/server/index.ts even with sibling middleware.ts |

**queue-monitor.ts assertion deferred to Plan 05:** Both fixture 08 and 09 verify.sh assert `test -f "$ROOT/queue-monitor.ts"`. This assertion fails at Plan 02 completion because `apply_root()` does not yet copy `queue-monitor.ts` — that copy step is Plan 05's D-11 expansion. The partial-GREEN state is bounded to exactly these 2 fixtures.

## Codex M-3 Verification

DIRTY `index.ts`-anchored project (lib-observability.ts content + `// LOCAL PATCH` appended) triggers REFUSE path. The `.observability-0019.patch` header shows:

```
# Anchor file: index.ts (canonical materialised filename per meta.yaml)
```

The diff excerpt in STDERR shows `diff index.ts` (not `diff lib-observability.ts`) — the operator sees their actual modified file. Template baseline is still read from `lib-observability.ts` (source-of-truth), mapped via `_template_name_for_anchor`.

## Canonicaliser Untouched

`git diff HEAD -- templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh | grep "canonicalize_awk\|CANON_AWK"` returns 0 lines. The canonicaliser block (lines 410–493) is byte-identical to the pre-edit state.

## GitNexus Blast Radius

All changed symbols are internal to `migrate-0019-sentry-crons-and-healthz.sh`:
- `_filter_index_ts_requires_co_anchor` — new function, no callers outside the find pipe
- `classify_stack` — called from `is_known_clean_wrapper`, `apply_root`, and `emit_refuse_artifacts_for` (all in same file)
- `resolve_anchor_files` — new function, called by `is_known_clean_wrapper` and `emit_refuse_artifacts` (same file)
- `_template_name_for_anchor` — new function, called by `is_known_clean_wrapper` and `emit_refuse_artifacts` (same file)
- `is_known_clean_wrapper` — called from the classify loop at line 634 (same file)
- `emit_refuse_artifacts_for` — called from `emit_refuse_artifacts` (same file)

No cross-file ripple. gitnexus_detect_changes scope is limited to the single engine file.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Helper function defined after its first call**

- **Found during:** Task 2.1 verification run
- **Issue:** `_filter_index_ts_requires_co_anchor` was initially placed after the find pipeline that pipes through it. Bash requires functions to be defined before they're called. This caused `command not found` at runtime, breaking all 10 previously-passing fixtures.
- **Fix:** Moved the function definition to line 208 (before `ROOTS=()` at line 235), ahead of all find pipeline calls.
- **Files modified:** `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`
- **Commit:** 38c9bdf

**2. [Rule 2 - Missing Critical] emit_refuse_artifacts diff loop still used stack_fingerprint_files**

- **Found during:** Task 2.2 implementation
- **Issue:** The plan specified rewiring `emit_refuse_artifacts_for` for codex M-3, but the diff loop inside `emit_refuse_artifacts()` (the outer caller) also iterated over `stack_fingerprint_files` — meaning the diff would silently skip for `index.ts` projects (file `$dir/lib-observability.ts` doesn't exist). The operator would see no diff output.
- **Fix:** Rewired the diff loop to use `resolve_anchor_files` with `_template_name_for_anchor` mapping.
- **Files modified:** `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`
- **Commit:** 38c9bdf (same commit)

## Known Stubs

None — the partial-GREEN state for fixtures 08/09 is documented and intentional. The `queue-monitor.ts` copy step is not a stub — it's a planned delivery in Plan 05 D-11.

## Self-Check: PASSED

- `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`: FOUND
- Commit `38c9bdf`: FOUND in git log
- `_filter_index_ts_requires_co_anchor`: FOUND (line 208)
- `resolve_anchor_files`: FOUND (line 409), 7 occurrences (>= 3 required)
- `_template_name_for_anchor`: FOUND (line 452)
- dist-path filter `*/dist/*|*/build/*|*/out/*`: FOUND
- `canonicalize_awk` changes: 0
- Test results: 10 PASS, 2 FAIL (08/09 queue-monitor.ts only — documented partial-GREEN)
