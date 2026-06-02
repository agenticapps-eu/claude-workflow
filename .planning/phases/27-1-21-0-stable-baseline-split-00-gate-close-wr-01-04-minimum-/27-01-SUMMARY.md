---
phase: 27
plan: "01"
subsystem: add-observability/templates
tags: [test-harness, shell, deno, supabase-edge, bug-fix]
dependency_graph:
  requires: []
  provides: [WR-01, WR-02]
  affects: [run-template-tests.sh, ts-supabase-edge/index.test.ts]
tech_stack:
  added: []
  patterns: [grep-c-vs-grep-oE idiom, finally-block cleanup]
key_files:
  modified:
    - add-observability/templates/run-template-tests.sh
    - add-observability/templates/ts-supabase-edge/index.test.ts
decisions:
  - "WR-01: used '|| true' (not a capture-then-default) to suppress grep exit-1 without appending a second zero"
  - "WR-02: _resetForTest() moved inside finally so it runs even when assertions throw; stray post-assertion call removed"
metrics:
  duration_minutes: 5
  completed_date: "2026-06-02T10:03:34Z"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
---

# Phase 27 Plan 01: WR-01/WR-02 Test Harness Fixes Summary

**One-liner:** Two surgical fixes — go-test counter double-count eliminated with `|| true`; D-02a finally block now guarantees `_resetForTest()` runs even on assertion failure.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | WR-01 — drop double-count on go-test counter | `9f92041` | run-template-tests.sh |
| 2 | WR-02 — add _resetForTest() to D-02a finally | `d660adf` | ts-supabase-edge/index.test.ts |

## What Was Done

**WR-01 (Task 1):** Lines 633-634 of `run-template-tests.sh` used `grep -c '^--- PASS' || echo "0"`. Because `grep -c` always emits a count (printing `0` on no match) AND exits 1 on no match, the `|| echo "0"` appended a second `0`, yielding the captured string `"0\n0"`. Fixed by replacing `|| echo "0"` with `|| true`, which only suppresses the exit-1 without emitting anything extra. The four `grep -oE … || echo "0"` firewall lines (128, 130, 558, 559) are untouched — those use `grep -oE` which prints nothing on no match, so `|| echo "0"` is the correct fallback there.

**WR-02 (Task 2):** The D-02a test `finally` block only restored `console.log`. The `_resetForTest()` cleanup call was located after the assertions (line 247), so it would not execute if an assertion threw. Moved `_resetForTest()` inside the `finally` block immediately after `console.log = origLog`, guaranteeing singleton state resets regardless of assertion outcome. The stray post-assertion call was removed. This matches the docstring at line 206 which already documented the intended cleanup pattern.

## Verification

- Content-based firewall check: exactly 4 `|| echo "0"` lines, all `grep -oE`; zero `grep -c … || echo "0"` — PASS
- `grep -Eq "grep -c '^--- PASS' || true"` — PASS
- `bash run-template-tests.sh ts-supabase-edge` → 57 passed, 0 failed, exit 0 — GREEN
- No new `_set*`/`_test*` export added to index.ts (HIGH-3 honored)

## Deviations from Plan

### Pre-existing state discovered

**WR-02 state:** The test file already had a `_resetForTest()` call at line 247, but it was placed AFTER the assertions (not inside the `finally` block). The plan's description said the `finally` block "currently reads: `console.log = origLog;`" with no cleanup — which was accurate about the `finally` block itself, but a standalone cleanup call did exist. The fix was still necessary: moved the call inside `finally` and removed the unreachable post-assertion duplicate. Net effect is identical to what the plan specified.

No other deviations. Plan executed as written.

## Known Stubs

None — both fixes are complete implementations, not stubs.

## Threat Flags

None — no new attack surface introduced. Test harness and test file only.

## Self-Check: PASSED

- `9f92041` exists: confirmed via git log
- `d660adf` exists: confirmed via git log
- `add-observability/templates/run-template-tests.sh` — modified (WR-01 applied)
- `add-observability/templates/ts-supabase-edge/index.test.ts` — modified (WR-02 applied)
- ts-supabase-edge suite: 57 passed, 0 failed
