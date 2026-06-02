---
phase: 27-1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum
reviewed: 2026-06-02T13:15:00Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - add-observability/templates/openrouter-monitor/src/index.ts
  - add-observability/templates/openrouter-monitor/src/observability/index.test.ts
  - add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts
  - add-observability/templates/ts-cloudflare-pages/lib-observability.test.ts
  - add-observability/templates/ts-supabase-edge/index.test.ts
  - add-observability/templates/run-template-tests.sh
  - add-observability/templates/.gitignore
  - migrations/run-tests.sh
  - CHANGELOG.md
  - docs/decisions/0035-shared-extraction-boundaries.md
  - SPLIT-00-PREREQUISITES.md
  - SPLIT-01-agenticapps-shared.md
findings:
  critical: 0
  warning: 1
  info: 2
  total: 3
status: issues_found
---

# Phase 27: Code Review Report

**Reviewed:** 2026-06-02T13:15:00Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

This phase is primarily docs, test-hardening, and one targeted runtime change (WR-04). The diff is well-scoped. No critical security issues or data-loss bugs were found.

The WR-04 change in `openrouter-monitor/src/index.ts` is correct: the inline Sentry options object is replaced by a call to `buildSentryOptions(env)`, which reads from the openrouter `observability/index.ts` implementation. The concrete values (`SERVICE_DEFAULT = "openrouter-monitor"`, `TRACE_SAMPLE_RATE = 0.1`, `DEPLOY_ENV ?? "dev"`) match the test assertions in `openrouter-monitor/src/observability/index.test.ts` exactly.

The WR-02 supabase-edge fix (`_resetForTest()` moved into the `finally` block) is structurally correct: cleanup now runs unconditionally, preventing singleton bleed. The move from trailing-statement to `finally` is the right fix.

The WR-01 shell fix (`grep -c ... || true` replacing `grep -c ... || echo "0"`) is correct. `grep -c` always prints a numeric count to stdout on no-match (it exits non-zero but the count is `0`), so `|| echo "0"` was appending a second `0`, producing `"0\n0"` which `awk '{print $1}'` would correctly read as `0` — but it also produced misleading two-line strings in the local `PASSED`/`FAILED` variables. The `|| true` fix is correct and safe.

The `migrations/run-tests.sh` changes are comment-only boundary annotations (`# SHARED` / `# WORKFLOW`). No executable code was changed; the annotations are syntactically valid shell comments.

One warning and two info-level findings are noted below.

## Warnings

### WR-01: `buildSentryOptions` default value in openrouter test (Test B) asserts the right SERVICE_DEFAULT but this is not a template token

**File:** `add-observability/templates/openrouter-monitor/src/observability/index.test.ts:54`
**Issue:** Test B asserts `expect(opts.release).toBe("openrouter-monitor")` — a hardcoded string. In the cf-worker and cf-pages tests (which go through the template harness), the equivalent assertion uses `"test-service"` because the harness substitutes `{{SERVICE_NAME}}` before running. The openrouter-monitor test file does NOT go through the `run-template-tests.sh` token substitution pipeline (it is a tracked file driven by the locked `package-lock.json`, not a materialized template). This means the `"openrouter-monitor"` literal is correct for this file's role, but if a future developer misreads the comment `// SERVICE_DEFAULT` and thinks this is a substitutable token, they may incorrectly move the file into the template harness pipeline, causing the assertion to silently change value (the harness substitutes `{{SERVICE_NAME}}` → `"test-service"`, which would NOT equal `"openrouter-monitor"`, causing a test failure). The risk is currently theoretical — the file is correctly placed — but the absence of an explicit comment explaining WHY this file is not a template (unlike cf-worker/cf-pages) creates a maintenance trap.
**Fix:** Add a one-line comment adjacent to the assertion clarifying the non-template nature:
```typescript
// Not a template token — this file is tracked directly (not materialized by run-template-tests.sh)
expect(opts.release).toBe("openrouter-monitor"); // SERVICE_DEFAULT for openrouter-monitor
```

## Info

### IN-01: D-02a test in cf-worker/cf-pages directly reassigns `console.log` instead of using `vi.spyOn`

**File:** `add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts:294-295`
**File:** `add-observability/templates/ts-cloudflare-pages/lib-observability.test.ts:636-637`
**Issue:** The D-02a `init() repeated-init determinism` test block in both cf-worker and cf-pages uses direct property reassignment (`console.log = (line: string) => { captured.push(line); }`) and then restores via `console.log = origLog` in a `finally` block. This contrasts with the rest of the test suite in the same files, which uses `vi.spyOn(console, "log").mockImplementation(...)` / `spy.mockRestore()`. Direct reassignment bypasses vitest's spy infrastructure and can interfere with any other spy on `console.log` that happens to be active during the test. The `beforeEach` setup in cf-pages (line 254) installs `logSpy = vi.spyOn(console, "log").mockImplementation(() => {})` — that spy is active during the D-02a block, which means the D-02a manual reassignment is competing with vitest's spy chain. In practice `captured.push(line)` may receive zero entries if vitest's mock intercepts first, depending on spy ordering. The tests have reportedly been GREEN, which suggests the direct assignment wins over the vi.fn mock, but it is fragile.
**Fix:** Replace the direct `console.log =` assignment with `vi.spyOn` in the D-02a block to be consistent with the file's own pattern:
```typescript
const logSpy = vi.spyOn(console, "log").mockImplementation((line: string) => {
  captured.push(line);
});
try {
  init(...); logEvent(...);
  init(...); logEvent(...);
} finally {
  logSpy.mockRestore();
}
```
Note: the supabase-edge variant uses the same direct-assignment pattern but that test runner is Deno (no vitest spies), so it is correct there.

### IN-02: `SPLIT-01-agenticapps-shared.md` Phase B filter-repo command references `bin/gsd-tools.cjs`

**File:** `SPLIT-01-agenticapps-shared.md:285`
**Issue:** The Phase B section (lines 280-294) includes an illustrative `git filter-repo` command that still references `bin/gsd-tools.cjs` and `--path-rename bin/gsd-tools.cjs:bin/shared-tools.cjs`. The `CORRECTION` blockquote earlier in the file (lines 42-63) correctly explains that `bin/gsd-tools.cjs` does not exist in this repo and the real extraction target is `migrations/run-tests.sh`. However Phase B's illustrative command was not updated to match. An executor following the Phase B steps literally would run a no-op `filter-repo` that extracts nothing (the path does not exist) and then proceed to Phase C thinking extraction succeeded.
**Fix:** Update the Phase B illustrative command to reflect the corrected extraction target:
```bash
git filter-repo --path migrations/run-tests.sh \
  --path migrations/lib/ \
  --path migrations/test-fixtures/_example/
```
Or add an explicit note directly in Phase B (not just the `CORRECTION` block in a different section) that the command is superseded.

---

_Reviewed: 2026-06-02T13:15:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
