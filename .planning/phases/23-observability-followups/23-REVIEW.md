---
phase: 23-observability-followups
reviewed: 2026-05-29T20:00:00Z
depth: standard
files_reviewed: 25
files_reviewed_list:
  - add-observability/CHANGELOG.md
  - docs/decisions/0029-cron-monitor-sdk-composition.md
  - migrations/test-fixtures/0019/07-allow-partial-emits-patches/setup.sh
  - migrations/test-fixtures/0019/07-allow-partial-emits-patches/verify.sh
  - migrations/test-fixtures/0019/07-allow-partial-emits-patches/expected-exit
  - add-observability/SKILL.md
  - add-observability/init/INIT.md
  - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts
  - add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts
  - add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts
  - add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts
  - add-observability/templates/ts-cloudflare-pages/cron-monitor.ts
  - add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts
  - add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts
  - add-observability/templates/ts-cloudflare-pages/healthz-snippet.test.ts
  - add-observability/templates/ts-supabase-edge/cron-monitor.ts
  - add-observability/templates/ts-supabase-edge/cron-monitor.test.ts
  - add-observability/templates/ts-supabase-edge/healthz-snippet.ts
  - add-observability/templates/ts-supabase-edge/healthz-snippet.test.ts
  - add-observability/templates/go-fly-http/cron_monitor.go
  - add-observability/templates/go-fly-http/healthz_snippet.go
  - add-observability/templates/go-fly-http/healthz_snippet_test.go
  - migrations/run-tests.sh
  - migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/verify.sh
  - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
findings:
  critical: 0
  warning: 3
  info: 4
  total: 7
status: issues_found
---

# Phase 23: Code Review Report

**Reviewed:** 2026-05-29T20:00:00Z
**Depth:** standard
**Files Reviewed:** 25
**Status:** issues_found

## Summary

This phase ships the Guarded Shape A `withCronMonitor` refactor (ADR-0029) across three TS stacks, per-probe timeout support for all four stacks' healthz snippets, the D-07 honest reframe of migration-0019's default-refuse semantics, and the F3 split-trap design. The core Guarded Shape A logic is correctly implemented in all three TS stacks: `handlerStarted` is set *inside* the callback (not before), and the catch path correctly distinguishes pre-callback from post-callback failures. The AbortController + setTimeout/clearTimeout healthz timeout pattern is correctly applied (not Promise.race). The split-trap design is correctly implemented. No critical issues were found.

Three warnings and four informational items follow.

## Warnings

### WR-01: Pages healthz KV probe does not pass AbortSignal — abort event fires too late

**File:** `add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts:122`

**Issue:** The Pages KV probe calls `env.OBSERVABILITY_KV!.get("healthz-probe")` with no argument — unlike the Worker variant which passes `controller.signal` as the second argument. The timeout mechanism relies on the `abort` listener on `controller.signal` to reject the Promise when the timeout fires, which works correctly. However, if the KV `get` call itself completes (resolves or rejects) before the abort event fires, a race exists: the abort listener added *inside* the Promise constructor may fire after `resolve()` has already settled the Promise, causing the abort event to invoke `reject(...)` on an already-settled Promise. This is benign for Promise semantics (ignored) but it means the abort event listener created in this Pattern is never cleaned up. In contrast, the Worker variant passes `signal` directly to `get()` so the underlying KV binding can cancel the I/O and the abort listener path is the primary path.

More importantly: without passing the signal to `.get()`, if the KV binding implementation ignores the abort listener (i.e. the listener never fires), the timeout race depends entirely on the `setTimeout` callback calling `controller.abort()` which then fires the `abort` event. This works, but the abort listener is the only rejection path — the `env.OBSERVABILITY_KV!.get(...)` call itself cannot be cancelled. This is a documentation gap rather than a hard bug, but it means probe timeout behaviour is subtly weaker on Pages KV than on Worker KV.

The Worker snippet's `HealthzEnv` interface types `OBSERVABILITY_KV.get` as `(key: string, signal?: AbortSignal) => Promise<string | null>` (line 65), correctly threading the signal. The Pages `HealthzEnv` types `OBSERVABILITY_KV.get` as `(key: string) => Promise<string | null>` (line 73), with no signal parameter at all, which makes passing the signal impossible without a cast.

**Fix:** Update the Pages `HealthzEnv.OBSERVABILITY_KV` interface to accept an optional `signal` parameter and pass `controller.signal` to `.get()`:

```typescript
OBSERVABILITY_KV?: { get: (key: string, signal?: AbortSignal) => Promise<string | null> };
```

And in the probe call:
```typescript
env.OBSERVABILITY_KV!.get("healthz-probe", controller.signal)
  .then(() => resolve())
  .catch(reject);
```

This makes the Pages probe consistent with the Worker probe and enables the KV binding to cancel the in-flight I/O on abort.

---

### WR-02: Go healthz upstream probe goroutine leaks when timeout fires first

**File:** `add-observability/templates/go-fly-http/healthz_snippet.go:138-155`

**Issue:** The upstream probe fires a goroutine that calls `deps.Upstream.Get("https://internal/healthz")`. When `time.After(probeTimeout)` fires first, the function returns `"timeout"` and moves on. The goroutine continues running in the background until `Get` naturally completes, at which point it attempts to send on `done` (a buffered channel of size 1). Because the channel has capacity 1 and no receiver is left, the send succeeds but the goroutine then exits. This is correctly documented in CHANGELOG.md ("caps handler latency only; underlying `Get(url)` outbound call may continue in background until natural completion — codex MEDIUM-5 honest documentation") and in the healthz_snippet.go inline comment.

The issue is that the `http.Response` body returned by `Get` in the goroutine is **never closed** when the timeout fires before the goroutine completes. If `Get` succeeds after the timeout, `res.resp` has a non-nil body that is placed in `done` but never read. The goroutine at lines 139-142 does close `res.resp.Body` when it *does* read the channel result (line 151), but the timeout branch at line 154 (`case <-time.After(probeTimeout):`) simply returns, leaving the goroutine running with a response body that will eventually be placed into a channel with no reader. The channel's buffer absorbs the send, but the `Body.Close()` path is never reached.

```go
case res := <-done:
    // ...
    if res.resp.Body != nil {
        _ = res.resp.Body.Close()  // only reached when done fires first
    }
case <-time.After(probeTimeout):
    checks["upstream"] = "timeout"
    // goroutine still running; if Get() later returns, resp.Body leaks
}
```

**Fix:** Drain and close the response body in a deferred goroutine when the timeout fires, or use `context.WithTimeout` on an `http.Client` that honours context cancellation (which requires changing the `upstreamProbe` interface). The minimal fix using the current interface:

```go
case <-time.After(probeTimeout):
    checks["upstream"] = "timeout"
    // Drain response body when goroutine eventually completes.
    go func() {
        if res := <-done; res.resp != nil && res.resp.Body != nil {
            _ = res.resp.Body.Close()
        }
    }()
```

This correctly cleans up the response body without changing the probe interface or adding context propagation complexity. The honest-docs note in CHANGELOG.md should be updated to mention the deferred-close rather than leaving the body unclosed.

---

### WR-03: Supabase cron-monitor.ts `_setWithMonitorForTest` has no restore path — module-level seam is permanently overwritten after tests without explicit reset

**File:** `add-observability/templates/ts-supabase-edge/cron-monitor.ts:91-93`

**Issue:** The `_setWithMonitorForTest` export (lines 91-93) accepts a `WithMonitorFn` but not `null`. The test file's `resetWithMonitor()` function (cron-monitor.test.ts line 57-59) restores a passthrough by calling `_setWithMonitorForTest(async (_slug, cb) => cb())` — but this is a *new anonymous function*, not the original `Sentry.withMonitor`. Unlike `_setCaptureCheckInForTest` (which accepts `null` as the sentinel for "restore real SDK"), `_setWithMonitorForTest` has no such path. The `null`-restore path was documented as needed in the companion `_setCaptureCheckInForTest` pattern (lines 73-77) but was not implemented for `_setWithMonitorForTest`.

The consequence is: production code that calls `_setWithMonitorForTest` inadvertently (e.g. via a mistaken import chain in a real Deno deployment) cannot restore the real `Sentry.withMonitor`. The passthrough lambda in `resetWithMonitor` is functionally correct for tests but it is a different function object from `Sentry.withMonitor`, so if `Sentry.withMonitor` is ever read for type/identity comparison the seam is not transparent.

Additionally, the test comment on line 64 ("no longer needed for test assertions after Guarded Shape A refactor, but the export must remain to avoid breaking the module contract") suggests `_setCaptureCheckInForTest` is dead code left for backwards compatibility. This is acceptable but worth noting. The `captureCheckIn` destructure at lines 29-31 is also effectively unused in the new implementation (the `captureCheckInFn` variable at line 70 is assigned but only called if the production path ever invokes it — which the new Guarded Shape A code does not since `_withMonitorImpl` now wraps the entire lifecycle).

**Fix:** Add a null-sentinel restore path to `_setWithMonitorForTest` consistent with `_setCaptureCheckInForTest`:

```typescript
export function _setWithMonitorForTest(impl: WithMonitorFn | null): void {
  _withMonitorImpl = impl === null
    ? (Sentry as any).withMonitor as WithMonitorFn
    : impl;
}
```

And update `resetWithMonitor()` in the test file to call `_setWithMonitorForTest(null)` instead of the anonymous lambda.

---

## Info

### IN-01: Supabase cron-monitor.ts `captureCheckIn` import + `captureCheckInFn` variable are now dead code

**File:** `add-observability/templates/ts-supabase-edge/cron-monitor.ts:29-31, 65-77`

**Issue:** After the Guarded Shape A refactor, `captureCheckInFn` (the module-level seam wrapping `sentryCaptureCheckIn`) is never called — `withCronMonitor` now delegates to `_withMonitorImpl` exclusively. The `captureCheckIn` destructure (lines 29-31), `CaptureCheckInFn` type (lines 65-68), `captureCheckInFn` variable (line 70), and `_setCaptureCheckInForTest` export (lines 73-77) are all unreachable from the production code path. The test file explicitly notes this on line 64.

This is dead code that increases reader cognitive load and was preserved for backwards-compatibility (the export contract). It should be cleaned up or formally annotated as a deprecated-but-retained export.

**Fix:** Either remove the dead seam entirely (breaking change for any consumers that imported `_setCaptureCheckInForTest`) or add a `@deprecated` JSDoc annotation:

```typescript
/** @deprecated — unused after Guarded Shape A refactor (ADR-0029). Retained for
 *  backwards-compatibility. Will be removed in v0.8.0. */
export function _setCaptureCheckInForTest(fn: CaptureCheckInFn | null): void { ... }
```

---

### IN-02: Fixture 07 `verify.sh` comment header has a subtle semantic inversion on line 2

**File:** `migrations/test-fixtures/0019/07-allow-partial-emits-patches/verify.sh:2-5`

**Issue:** The comment on lines 2-5 states "Engine applies clean roots and skips dirty root; exits 0. Under --allow-partial, patches emitted for ALL roots (dirty AND clean)." However, the actual test on line 18 checks the engine exits 0 (correct), then lines 29-32 assert that the dirty root did NOT receive `cron-monitor.ts` or `healthz-snippet.ts` (dirty root is skipped), which contradicts the header comment's phrase "Engine applies clean roots and skips dirty root" — which is accurate for the *engine* behaviour but the comment structure implies the migration installs files into the dirty root, which it explicitly does not. The patch (not the production files) is written to the dirty root.

This is a documentation inconsistency: the verify.sh correctly tests the right thing (patches at all 3 roots, production files only at clean roots), but the summary comment is ambiguous about what "applies" and "patches" mean in this context.

**Fix:** Reword the header to be unambiguous:
```bash
# Verify fixture 07: --allow-partial migrates clean roots (files installed) and
# skips dirty root (no files installed). Patches emitted for ALL roots (clean +
# dirty) for reference. Engine exits 0. Version bumped (clean roots migrated).
```

---

### IN-03: `test_skill_md_version_matches_latest_migration_to_version` reads from `skill/SKILL.md` but the canonical path is `add-observability/SKILL.md`

**File:** `migrations/run-tests.sh:2161`

**Issue:** The version drift test reads `skill_version` from `grep ^version: skill/SKILL.md` (line 2161). The `add-observability` skill's SKILL.md lives at `add-observability/SKILL.md` (confirmed by SKILL.md location in the review scope), not `skill/SKILL.md`. The test will fail with "No such file or directory" or silently return an empty `skill_version` string if run from the repo root.

The test's dispatcher block at lines 2438-2448 guards with `declare -F` so it will still *run* if the function is defined, but `skill_version` will be empty and the comparison `[ "$skill_version" = "$migration_to_version" ]` will fail with a FAIL verdict on any environment where `skill/SKILL.md` does not exist.

**Fix:**
```bash
skill_version=$(grep ^version: add-observability/SKILL.md | awk '{print $2}')
```

Alternatively, if this is a dispatcher-skill test (testing `skill/SKILL.md` at the workflow-core root), the path should be explicitly documented — but the CHANGELOG entry for F4 refers to `add-observability/SKILL.md` bump (0.6.0 → 0.7.0), so the intent is clearly to track the `add-observability` skill version.

---

### IN-04: `run-tests.sh` RETURN trap in `test_migration_0001` uses single-quoted variable in temp dir names which may fail cleanup on SIGINT mid-function

**File:** `migrations/run-tests.sh:201-202`

**Issue:** `test_migration_0001` registers a RETURN trap (line 202: `trap "rm -rf '$before_dir' '$after_dir'" RETURN`) using *single-quoted* variable names. In bash, single quotes inside a double-quoted trap string are treated as literal characters, not as quoting for the expanded variable. If `$before_dir` or `$after_dir` contains spaces, the `rm -rf` call will fail silently or misinterpret the paths. The temp dir names are created with `mktemp -d -t migration-0001-*` which should not produce spaces under standard mktemp implementations, so this is low-risk in practice.

More notably, the RETURN trap is per-function-scope and fires when the function returns normally OR when the function is exited via `return`. It does NOT fire on SIGINT if the signal terminates the shell before the function returns. This is a pre-existing pattern inherited from earlier migration test functions and not introduced by this phase, but it is worth noting for completeness.

**Fix (minimal):** Use double-quoted variables in the trap string:
```bash
trap "rm -rf \"$before_dir\" \"$after_dir\"" RETURN
```

This is a low-severity documentation/style note given the predictable mktemp naming, not a real security issue.

---

_Reviewed: 2026-05-29T20:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
