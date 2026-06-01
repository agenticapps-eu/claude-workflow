---
phase: 25-fix-0019-engine-and-cron-wrappers
reviewed: 2026-06-01T00:00:00Z
depth: standard
files_reviewed: 20
files_reviewed_list:
  - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
  - templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh
  - migrations/run-tests.sh
  - add-observability/templates/run-template-tests.sh
  - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts
  - add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts
  - add-observability/templates/ts-cloudflare-worker/queue-monitor.ts
  - add-observability/templates/ts-cloudflare-worker/queue-monitor.test.ts
  - add-observability/templates/ts-cloudflare-pages/cron-monitor.ts
  - add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts
  - add-observability/templates/ts-cloudflare-pages/queue-monitor.ts
  - add-observability/templates/ts-cloudflare-pages/queue-monitor.test.ts
  - add-observability/templates/ts-supabase-edge/cron-monitor.ts
  - add-observability/templates/ts-supabase-edge/cron-monitor.test.ts
  - add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts
  - migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts
  - migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/env.ts
  - migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/tsconfig.json
  - migrations/test-fixtures/0021/common-setup.sh
findings:
  critical: 0
  warning: 4
  info: 5
  total: 9
status: issues_found
---

# Phase 25: Code Review Report

**Reviewed:** 2026-06-01
**Depth:** standard
**Files Reviewed:** 20
**Status:** issues_found

## Summary

Phase 25 delivers four targeted fixes for GitHub issue #56 findings. The overall
implementation is sound: the discriminated-union schedule type (F2), the narrowed
generic (F3), the queue-monitor wrapper (F4), and the engine anchor-file handling
(F1) are all correct in their core logic.

The critical-to-correctness finding is nil. The four warnings represent cases where
incorrect inputs or edge conditions produce silently wrong behaviour — none is a
security vulnerability, but two (WR-01, WR-02) affect migration correctness in
detectable real-world scenarios. The info items are minor consistency gaps and a
test-isolation risk.

---

## Warnings

### WR-01: migrate-0021 uses `local` inside `is_clean_to_apply_021` called from a `for` loop — shadowing risk with `local_dir`/`local_stack` in the DIRTY loop body

**File:** `templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh:601-606`

**Issue:** The DIRTY refuse loop declares `local_dir` and `local_stack` as plain
(non-`local`) variables at lines 603-604:

```bash
for i in "${!DIRTY_DIRS[@]}"; do
  local_dir="${DIRTY_DIRS[$i]}"
  local_stack="${DIRTY_STACKS[$i]}"
  emit_refuse_artifacts_021 "$local_dir" "$local_stack"
```

These are script-global variables (set outside any function). If `emit_refuse_artifacts_021`
or any function it calls were to declare `local local_dir` or `local local_stack` (they
don't today), the outer loop's names would be shadowed for subsequent iterations. More
concretely: the naming `local_dir`/`local_stack` reads as if they were meant to be
`local` declarations inside a function, but this code executes in the top-level script
scope. The pattern is inconsistent with how the same loop is written in the 0019 engine
(which uses `dir` and `stack` as loop-local names inside `apply_root`). If a future
refactor wraps this loop body in a function and forgets to convert these to true `local`
declarations, the loop will silently iterate against a stale `local_dir`.

**Fix:** Rename to plain loop-iteration names consistent with the rest of the script,
or wrap in a function with `local`:

```bash
for i in "${!DIRTY_DIRS[@]}"; do
  dir="${DIRTY_DIRS[$i]}"
  stack="${DIRTY_STACKS[$i]}"
  emit_refuse_artifacts_021 "$dir" "$stack"
  warn "  $dir — see .observability-0021.patch"
done
```

---

### WR-02: migrate-0021 `apply_root_021` returns 0 for `go-fly-http` and `unknown` stacks — apply loop counts them as migrations

**File:** `templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh:547-554`

**Issue:** The `apply_root_021` function falls through to `return 0` for `go-fly-http`
(D-12 skip) and `unknown` stacks after printing an info/skip message. The apply loop
at lines 626-629 calls `apply_root_021 "$dir" "$stack" || EXIT_CODE=1`, and the final
`bump_version` is called only when `EXIT_CODE -eq 0`. Since `go-fly-http` roots would
never appear in `CLEAN_DIRS` (they are filtered into `SKIP_UNSUPPORTED` during pass 1
at lines 575-580), this path is unreachable in practice. However, if the pass-1 filter
ever changes to let `go-fly-http` through to `CLEAN_DIRS`, `apply_root_021` silently
succeeds, version is bumped, but no actual files were written for that stack — leaving
the project at 1.19.0 content with a 1.20.0 version marker.

The deeper issue is that there is no test fixture for the pass-1 guard path to verify
`go-fly-http` never reaches `apply_root_021`. Fixture 01/03 do not explicitly assert the
SKIP_UNSUPPORTED count.

**Fix:** Return a non-zero sentinel from the `go-fly-http` arm of `apply_root_021` to
make the skip explicit and detectable by the caller:

```bash
go-fly-http)
  info "  SKIP: go-fly-http out of scope per Phase 25 D-12"
  return 0  # intentional skip — not an error
  ;;
```

This is fine as-is (0 is correct for "intentionally skipped"). The real fix is adding a
`SKIP_ALREADY` counter path: the caller should check whether `CLEAN_DIRS` ever contains
a `go-fly-http` entry and warn loudly rather than silently no-op. As written the guard
relies solely on the pass-1 filter being correct — add a `[[ "$stack" == "go-fly-http" ]]`
assertion at the top of `apply_root_021` and treat it as a programming error (return 1)
rather than a silent skip.

---

### WR-03: cf-pages `queue-monitor.ts` imports `isConfigured` from `./cron-monitor` but the cf-pages `isConfigured` uses `Record<string, unknown>` while `withQueueMonitor`'s generic `E` is narrower

**File:** `add-observability/templates/ts-cloudflare-pages/queue-monitor.ts:50,99-100`

**Issue:** `withQueueMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>` (line
92-95) accepts narrower `E` types. At line 99-100 it calls `isConfigured(env)` where
`isConfigured` is imported from `./cron-monitor` and has the signature:

```ts
export function isConfigured(env: Record<string, unknown>): boolean
```

Because `env` is of type `E extends { SENTRY_DSN?: string; ... }` — not
`Record<string, unknown>` — passing it to `isConfigured` requires `E` to also satisfy
the index signature `[key: string]: unknown`, which `E` does NOT. This is structurally
safe in JavaScript (structural subtyping), and TypeScript with `strict: true` would
accept it because `E` is constrained to have the properties `isConfigured` actually reads.
However it creates an API surface inconsistency: the cf-worker `isConfigured` correctly
uses `env: { SENTRY_DSN?: string }` (narrowed per D-19/D-05), while the cf-pages variant
still uses `Record<string, unknown>` (line 57 of cf-pages cron-monitor.ts). When
`withQueueMonitor` imports `isConfigured` from cf-pages `cron-monitor.ts` and passes its
narrowed `E`, TypeScript may or may not reject this depending on the exact `E` used —
an `E` without an index signature satisfying `{ SENTRY_DSN?: string }` cannot be
assigned to `Record<string, unknown>` in strict mode.

**Fix:** Either:
1. Update the cf-pages `isConfigured` signature to match the cf-worker variant:
   `export function isConfigured(env: { SENTRY_DSN?: string }): boolean`
2. Or widen the `withQueueMonitor` generic in cf-pages to `E extends Record<string, unknown>`
   (matching the cf-pages cron-monitor pattern) for consistency.

Option 1 is preferable as it closes the inconsistency gap between the two stacks' exported
contracts (D-19).

---

### WR-04: `run-template-tests.sh` trap override in `run_ts_cloudflare_worker` and `run_ts_cloudflare_pages` — the explicit `trap - EXIT; rm -rf "$WORKDIR"` on the fast-fail paths clears the harness-level EXIT trap

**File:** `add-observability/templates/run-template-tests.sh:208,231,330,353`

**Issue:** Each stack runner sets a per-WORKDIR trap:
```bash
trap "rm -rf '$WORKDIR'" EXIT
```
then clears it on the fast-fail path:
```bash
trap - EXIT; rm -rf "$WORKDIR"
return 1
```
This `trap - EXIT` clears the EXIT trap entirely for the enclosing shell. In bash,
`trap - SIGNAL` inside a function that was called from a subshell inherits the parent
trap state. Since these functions do not run in a subshell (they are called directly via
`run_stack`), `trap - EXIT` replaces the enclosing script's `set -euo pipefail`-aware
EXIT handler with nothing. If any subsequent code in the main dispatcher body exits
non-zero after the first stack's failure, temp dirs from other stacks may leak. The
correct pattern is `trap '' EXIT` (set to empty handler) to suppress the inherited
trap, or use a wrapper subshell.

In practice the `WORKDIR` cleanup is unconditional on the success path (the final
`trap - EXIT; rm -rf "$WORKDIR"` runs after `return $EXIT_CODE`), and the failure path
also cleans up before returning, so leakage only occurs if the process is killed between
`return 1` and the cleanup — a minor risk. The real concern is the interaction with the
harness's own `set -euo pipefail`: after `trap - EXIT` the harness no longer has a
guaranteed cleanup on abrupt termination.

**Fix:** Use a subshell for each stack runner, or scope the trap correctly:

```bash
# Option A: run the runner in a subshell so trap - EXIT stays scoped
( run_ts_cloudflare_worker ) || OVERALL_EXIT=1

# Option B: replace trap - EXIT with a no-op
trap '' EXIT; rm -rf "$WORKDIR"; return 1
```

---

## Info

### IN-01: openrouter-monitor `cron-monitor.ts` is a byte-for-byte copy of the cf-worker template — not imported, just duplicated

**File:** `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts`

**Issue:** This file is byte-identical to
`add-observability/templates/ts-cloudflare-worker/cron-monitor.ts` (both import from
`@sentry/cloudflare`, both export the narrowed `<E extends { SENTRY_DSN?: string; ... }>`
generic). There is no comment explaining why it is a copy rather than a symlink or
re-export. If the D-19 export contract changes in the future, this copy would need to be
updated separately. It is also not materialized by `run-template-tests.sh` (the openrouter
stack has no test runner wired in the harness), so regressions in this copy are not
caught by the CI template-test suite.

**Fix:** Either add a comment explaining the copy rationale, or wire the openrouter stack
into `run-template-tests.sh`. If the openrouter template is intentionally identical to
the cf-worker template, document it as such so future editors know not to diverge them.

---

### IN-02: `run_0021_fixture` in `migrations/run-tests.sh` does not capture setup.sh errors — a failing setup silently passes

**File:** `migrations/run-tests.sh:2180-2185`

**Issue:** The 0021 fixture runner runs setup + verify in a single subshell:

```bash
(
  cd "$tmp"
  FIXTURES_ROOT="$fixtures" REPO_ROOT="$REPO_ROOT" bash "$dir/setup.sh"
  FIXTURES_ROOT="$fixtures" REPO_ROOT="$REPO_ROOT" bash "$dir/verify.sh"
)
```

With `set -euo pipefail` in the harness, a non-zero exit from `setup.sh` will cause the
subshell to exit non-zero, which `run_0021_fixture` then sees as `rc != 0` and marks as
FAIL. This is different from every other migration's fixture runner (0017, 0018, 0019)
which captures setup.sh exit separately with an explicit check and a distinct error
message:

```bash
if [ -x "$fixdir/setup.sh" ]; then
  ( ... "$fixdir/setup.sh" ...) || {
    echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
    FAIL=$((FAIL+1)); return
  }
fi
```

The 0021 runner does not distinguish "setup.sh failed" from "verify.sh failed" — both
produce `FAIL $fixname` with no diagnostic detail. A broken setup produces a confusing
failure message ("FAIL 01-fresh-1.19.0-apply" with no indication setup was the culprit).

**Fix:** Split setup and verify into separate invocations with an intermediate check,
matching the pattern used by 0017/0018/0019 fixture runners.

---

### IN-03: `stack_fingerprint_files` in migrate-0019 is never called in pass 1 — dead code path after resolve_anchor_files was introduced

**File:** `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:386-394`

**Issue:** `stack_fingerprint_files` returns space-separated filenames for each stack
and was the original canonical-file resolver before `resolve_anchor_files` was added
(D-01). After the D-01 refactor, all call sites in pass 1 (`is_known_clean_wrapper`) use
`resolve_anchor_files` instead. The only remaining call to `stack_fingerprint_files` is
inside `emit_refuse_artifacts` at line 764 as the fallback for `resolve_anchor_files`
failure: `files=$(resolve_anchor_files ...) || files=$(stack_fingerprint_files ...)`.

If `resolve_anchor_files` fails (returns 1), `stack_fingerprint_files` is the fallback.
But `resolve_anchor_files` returns 1 only when neither `index.ts` nor `lib-observability.ts`
exists in the project. In that case `stack_fingerprint_files` would return
`"lib-observability.ts middleware.ts"` for cf-worker, which the diff loop would try to
open — but `lib-observability.ts` doesn't exist (that's why `resolve_anchor_files`
failed). The fallback produces a no-op diff (both `[ -f "$tmpl" ]` and `[ -f "$project_file" ]`
checks fail silently), so the diff section of the refuse artefact is empty. This is
confusing but not harmful. The function itself is not dead — it serves as a last-resort
fallback — but the fallback path produces a misleading silent no-diff output.

**Fix:** In the `emit_refuse_artifacts` fallback, emit a warning when
`resolve_anchor_files` fails rather than silently falling back to `stack_fingerprint_files`:

```bash
local files
files=$(resolve_anchor_files "$dir" "$stack") || {
  warn "  cannot resolve anchor files for $dir (stack: $stack); diff omitted"
  continue
}
```

---

### IN-04: `CronMonitorSchedule` D-16 firewall test uses `expectTypeOf` value-level pin but does NOT use `afterEach` — if the `@ts-expect-error` test ever stops error, it becomes a false-positive runtime pass

**File:** `add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts:215-220`

**Issue:** The test at line 215:

```ts
it("interval variant REJECTS value: string at typecheck time (D-03 firewall)", () => {
  // @ts-expect-error — ...
  const bad: CronMonitorSchedule = { type: "interval", value: "5", unit: "minute" };
  void bad;
});
```

The `@ts-expect-error` directive is the correct firewall. If the discriminated union type
regresses (removing the `value: number` constraint), TypeScript would no longer error on
this line, and `@ts-expect-error` would itself become an error (the directive would be
"unused"). This is exactly the right pattern. However, the test is purely a compile-time
check — the runtime `it()` body has no assertion. Vitest would count this as a PASS even
if the `@ts-expect-error` were accidentally removed (e.g., a `// @ts-ignore` substitution
that suppresses without asserting an error). This is documented as "Pitfall 4" and
accepted by design.

No change required; documented for awareness. Same pattern exists in cf-pages
`cron-monitor.test.ts:205-210` and `ts-supabase-edge/cron-monitor.test.ts:321-327`.

---

### IN-05: `common-setup.sh` seeds v1.20.0 worker but not v1.20.0 pages — fixture 03 (`already-1.20.0-skip`) may be incomplete

**File:** `migrations/test-fixtures/0021/common-setup.sh:54-63`

**Issue:** `seed_v1_20_0_worker` seeds a complete post-1.20.0 worker state (cron-monitor.ts
from live template + queue-monitor.ts). There is no corresponding `seed_v1_20_0_pages`
function. If fixture `03-already-1.20.0-skip` only seeds a worker root and not a pages
root, the "all already-applied" branch of `is_clean_to_apply_021` is only exercised for
the worker stack. The twofold idempotency check for cf-pages in the "already at v1.20.0"
state would not be tested.

This is an info-level concern because the fixture may call `seed_v1_20_0_worker` for
both stacks (which would incidentally work since the templates are declared byte-symmetric
in Plan 04 SUMMARY), or may only test one stack. Without reading the fixture's `setup.sh`
directly this cannot be confirmed. The missing `seed_v1_20_0_pages` function is a signal
that pages was not considered.

**Fix:** Add `seed_v1_20_0_pages` mirroring `seed_v1_20_0_worker`, using
`ts-cloudflare-pages` templates and `_middleware.ts` instead of `middleware.ts`. Update
fixture 03's `setup.sh` to seed both stacks.

---

_Reviewed: 2026-06-01_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
