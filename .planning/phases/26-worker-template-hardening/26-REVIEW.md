---
phase: 26-worker-template-hardening
reviewed: 2026-06-01T00:00:00Z
depth: standard
files_reviewed: 38
files_reviewed_list:
  - add-observability/CHANGELOG.md
  - add-observability/SKILL.md
  - add-observability/templates/go-fly-http/.gitignore
  - add-observability/templates/go-fly-http/meta.yaml
  - add-observability/templates/go-fly-http/policy.md.template
  - add-observability/templates/openrouter-monitor/env-additions.md
  - add-observability/templates/openrouter-monitor/src/observability/index.test.ts
  - add-observability/templates/openrouter-monitor/src/observability/index.ts
  - add-observability/templates/run-template-tests.sh
  - add-observability/templates/ts-cloudflare-pages/.gitignore
  - add-observability/templates/ts-cloudflare-pages/env-additions.md
  - add-observability/templates/ts-cloudflare-pages/lib-observability.test.ts
  - add-observability/templates/ts-cloudflare-pages/lib-observability.ts
  - add-observability/templates/ts-cloudflare-pages/meta.yaml
  - add-observability/templates/ts-cloudflare-pages/policy.md.template
  - add-observability/templates/ts-cloudflare-worker/.gitignore
  - add-observability/templates/ts-cloudflare-worker/env-additions.md
  - add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts
  - add-observability/templates/ts-cloudflare-worker/lib-observability.ts
  - add-observability/templates/ts-cloudflare-worker/meta.yaml
  - add-observability/templates/ts-cloudflare-worker/policy.md.template
  - add-observability/templates/ts-react-vite/.gitignore
  - add-observability/templates/ts-react-vite/meta.yaml
  - add-observability/templates/ts-react-vite/policy.md.template
  - add-observability/templates/ts-supabase-edge/.gitignore
  - add-observability/templates/ts-supabase-edge/index.test.ts
  - add-observability/templates/ts-supabase-edge/meta.yaml
  - add-observability/templates/ts-supabase-edge/policy.md.template
  - CHANGELOG.md
  - docs/decisions/0034-observability-init-singleton-invariant.md
  - migrations/test-fixtures/0019/13-index-ts-without-observability-content/expected-exit
  - migrations/test-fixtures/0019/13-index-ts-without-observability-content/setup.sh
  - migrations/test-fixtures/0019/13-index-ts-without-observability-content/src/index.ts
  - migrations/test-fixtures/0019/13-index-ts-without-observability-content/src/middleware.ts
  - migrations/test-fixtures/0019/13-index-ts-without-observability-content/verify.sh
  - migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts
  - migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/verify.sh
  - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
findings:
  critical: 0
  warning: 4
  info: 7
  total: 11
status: issues_found
---

# Phase 26: Code Review Report

**Reviewed:** 2026-06-01T00:00:00Z
**Depth:** standard
**Files Reviewed:** 38
**Status:** issues_found

## Summary

Phase 26 ships three carry-forward defect closures from Phase 24's `/review` (DEF-1 `buildSentryOptions` helper, DEF-2 REDACTED_KEYS expansion, DEF-3 ADR-0034 + repeated-init determinism tests), one engine fix to migration-0019's classifier (content-marker firewall + fixture 13), one fixture TS1038 fix (0021/04), `run-template-tests.sh` pin hardening (vitest exact, sentry tilde), and `.gitignore` extension across 5 stacks. The change-set is template-surface plus one engine-script bugfix.

The work is generally high quality, well-documented with cross-references to the Phase 26 CONTEXT and ADR-0034, and follows the established Phase 22/23/25 ADR voice and structure. Cross-AI (codex + gemini) review corrections are visibly incorporated (HIGH-1 ADR runtime model, HIGH-2 env-pure helper, HIGH-3 no `_setTestEnv`, HIGH-4 vitest exact pin, MED-3 determinism terminology, MED-4 test decoupling).

Findings below are predominantly **correctness-adjacent** (no security issues; no bugs that block the contract):

- Four Warnings: a real cosmetic-bash bug in `grep -c` fallback handling; a test-isolation gap in the supabase-edge D-02a test; a coverage gap (DEF-1 helper has zero direct tests across 3 stacks); a stale CHANGELOG cross-ref claim about openrouter-monitor's entry file.
- Seven Info items: comment-consistency drift between three byte-symmetric test blocks; broad regex risk in the content-marker filter; semantic awkwardness of `release: SERVICE_NAME`; minor documentation precision items.

No Critical issues. The DEF-1/2/3 implementations match what ADR-0034 documents, and the engine fix is well-fenced (additive filter; regression fixture present).

## Warnings

### WR-01: `grep -c` fallback produces multi-line PASSED/FAILED counts in Go runner

**File:** `add-observability/templates/run-template-tests.sh:633-634`
**Issue:** `grep -c` already prints `0` (to stdout) when there are zero matches, AND exits 1. Combined with `|| echo "0"`, the resulting command substitution captures `"0\n0"` — two lines of output — and binds that to `PASSED` / `FAILED`. The subsequent `pass "[$STACK] ${PASSED} tests passed"` then prints "0\n0 tests passed", which is confusing in test output. The script's success/fail decision uses `$EXIT_CODE`, not these counts, so this is cosmetic — but it's a real bug.
**Fix:**
```bash
# Use head -1 to collapse the duplicate-zero, or use a different fallback pattern
PASSED=$(echo "$OUTPUT" | grep -c '^--- PASS' 2>/dev/null || true)
PASSED=${PASSED:-0}
FAILED=$(echo "$OUTPUT" | grep -c '^--- FAIL' 2>/dev/null || true)
FAILED=${FAILED:-0}
```
(The `grep -oE` paths at lines 558-559 do NOT have this bug because they pipe through a second grep that consumes empty input cleanly.)

### WR-02: Supabase-edge D-02a test leaks module state on failure

**File:** `add-observability/templates/ts-supabase-edge/index.test.ts:217-247`
**Issue:** The test sequence is `_resetForTest({...env-a})` → `init()` → console.log monkey-patch in try/finally → assertions → `_resetForTest()` cleanup at line 247. The cleanup is NOT inside a try/finally that wraps the assertions. If any `assertEquals` at lines 235-245 throws, control exits the test function before the trailing `_resetForTest()` runs, leaving the module's `initialized` flag set, `_testEnv` populated with the env-a values, and `registry` non-null. Because Deno test files share module state across tests in the same file, subsequent tests in `index.test.ts` (if any are added after this one) would observe leaked state.
**Fix:**
```typescript
Deno.test("D-02a init() repeated-init determinism: ...", () => {
  _resetForTest({ SENTRY_DSN: "dsn-a", DEPLOY_ENV: "env-a", SERVICE_NAME: "svc-a" });
  init();
  try {
    const captured: string[] = [];
    const origLog = console.log;
    console.log = (line: string) => { captured.push(line); };
    try {
      logEvent({ event: "probe-a", severity: "info" });
      init();
      logEvent({ event: "probe-b", severity: "info" });
    } finally {
      console.log = origLog;
    }
    assertEquals(captured.length, 2, "expected 2 console.log envelopes");
    // ...other assertions
  } finally {
    _resetForTest();  // always clean up even if an assertion failed
  }
});
```

### WR-03: `buildSentryOptions(env)` has zero direct test coverage

**File:** `add-observability/templates/ts-cloudflare-worker/lib-observability.ts:154-162`, `add-observability/templates/ts-cloudflare-pages/lib-observability.ts:161-169`, `add-observability/templates/openrouter-monitor/src/observability/index.ts:154-162`
**Issue:** Phase 26 DEF-1 ships `buildSentryOptions(env)` as a new exported helper across 3 stacks. The CHANGELOG explicitly notes the D-02a determinism tests deliberately do NOT depend on this helper (codex MED-4 decoupling). That decoupling is correct for DEF-3, but the side effect is that DEF-1's helper has zero direct tests. A regression that, say, accidentally returned `tracesSampleRate: 1.0` (omitting the `TRACE_SAMPLE_RATE` constant), or omitted `sendDefaultPii: false` (the PII-leak guard), or returned `dsn: env.DEPLOY_ENV` (a copy-paste swap), would land green. The decoupling argument forbids using DEF-1 inside DEF-3 tests — it does NOT forbid a standalone DEF-1 test.
**Fix:** Add a 4-assertion unit test per stack (3 stacks × 4 assertions = small surface):
```typescript
describe("buildSentryOptions (DEF-1)", () => {
  it("returns env-derived dsn/environment/release plus baked tracesSampleRate and sendDefaultPii:false", () => {
    const opts = buildSentryOptions({
      SENTRY_DSN: "https://k@o.ingest.sentry.io/1",
      DEPLOY_ENV: "production",
      SERVICE_NAME: "myapp",
    });
    expect(opts.dsn).toBe("https://k@o.ingest.sentry.io/1");
    expect(opts.environment).toBe("production");
    expect(opts.release).toBe("myapp");
    expect(opts.tracesSampleRate).toBe(0.1);  // TRACE_SAMPLE_RATE constant
    expect(opts.sendDefaultPii).toBe(false);
  });

  it("falls back to defaults when env values are absent", () => {
    const opts = buildSentryOptions({});
    expect(opts.dsn).toBeUndefined();
    expect(opts.environment).toBe("dev");
    expect(opts.release).toBe(SERVICE_DEFAULT);  // or hard-coded "{{SERVICE_NAME}}" expanded value
    expect(opts.sendDefaultPii).toBe(false);
  });
});
```
This adds ~20 lines per stack and gives DEF-1 the same independent-test treatment DEF-3 received.

### WR-04: CHANGELOG cites openrouter-monitor entry file as already following the new pattern, but it actually hand-rolls inline options

**File:** `add-observability/templates/openrouter-monitor/env-additions.md:25-27`, `add-observability/CHANGELOG.md:13`
**Issue:** env-additions.md says: "The openrouter-monitor's own `src/index.ts:46-66` follows this pattern manually today (env-derived `environment` and `release`); `buildSentryOptions` factors that pattern into a reusable helper that maintenance forks can adopt." But `src/observability/index.ts` adds the helper without updating the openrouter-monitor entry file (`src/index.ts`) to actually call it — the entry file still inlines the options object verbatim (per `head -70 src/index.ts | sed -n '40,70p'` output: literal `{ dsn: env.SENTRY_DSN, environment: env.DEPLOY_ENV ?? "dev", release: env.SERVICE_NAME ?? "openrouter-monitor", tracesSampleRate: 0.1, sendDefaultPii: false }`). The documentation describes the *opportunity* for the entry file to adopt the helper, but a reader of CHANGELOG line 13 ("Operators wire it at their entry file: `withSentry(env => buildSentryOptions(env), withObservability(handler))`") would reasonably expect the openrouter-monitor scaffold itself to already wire it that way as a demonstration. As shipped, the helper exists but no scaffolded code uses it.
**Fix:** Either (a) update `add-observability/templates/openrouter-monitor/src/index.ts` to import and call `buildSentryOptions(env)` (so the scaffold demonstrates the canonical wiring), or (b) tighten the env-additions.md / CHANGELOG language to say "the helper is exported for downstream consumers; greenfield wiring still inlines the options because openrouter-monitor is a worked-example scaffold for cron-monitor not for buildSentryOptions". Option (a) is preferable — it eliminates a "documented helper that isn't actually called anywhere in the scaffold" stale-spec risk.

## Info

### IN-01: D-02a test comment drift across the three byte-symmetric test blocks

**File:** `add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts:255`, `add-observability/templates/ts-cloudflare-pages/lib-observability.test.ts:597`, `add-observability/templates/openrouter-monitor/src/observability/index.test.ts:49`
**Issue:** CHANGELOG line 15 commits to "byte-symmetric" between these three blocks (codex MED-1 evidence target). The inline contract-naming comment differs:
- cf-worker:583,255 says `// cf-worker/openrouter contract = last-call-wins`
- cf-pages:597 says `// cf-worker/cf-pages/openrouter contract = last-call-wins`
- openrouter:49 says `// cf-worker/openrouter contract = last-call-wins`

cf-pages lists itself in the contract; the other two omit cf-pages. The blocks are functionally byte-symmetric but textually drift. Either harmonise all three to `cf-worker/cf-pages/openrouter` (most accurate per ADR-0034) or accept the drift but update CHANGELOG to weaken the byte-symmetry claim.
**Fix:** Search/replace the three sites to the same `cf-worker/cf-pages/openrouter contract = last-call-wins (NO initialized guard)` string.

### IN-02: Content-marker firewall regex includes bare `sentry` — broad enough to match unrelated Sentry usage

**File:** `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:230`
**Issue:** `grep -qiE "observability|lib-observability|withObservability|sentry|agenticapps:observability"` is case-insensitive and uses bare `sentry`, which matches @sentry/cloudflare, withSentry, Sentry.init, SENTRY_DSN — all canonical Sentry usage. The migration is *meant* to be permissive here (better to attempt migration on a likely candidate than to skip it), but a project using Sentry directly with a hand-rolled (non-add-observability) wrapper and the canonical `src/index.ts + src/middleware.ts` layout would still trigger classification and a `.observability-0019.patch` emission. The Phase 26 fixture 13 closes the *narrowest* false-positive class (vanilla Hono with zero Sentry); it does NOT close the "project uses Sentry but not this skill's wrapper" class. The existing dirty-content / canonicalize_awk pipeline catches that downstream, so the impact is "operator sees an unsolicited `.observability-0019.patch`" not "wrong content is written" — but worth a CHANGELOG note that fixture 13 closes the *vanilla-Hono* false-positive, not the *any-non-canonical-Sentry-wrapper* false-positive.
**Fix:** No code change. Optionally tighten the regex to require `lib-observability|withObservability|agenticapps:observability` (drop bare `sentry` and `observability`), but that loses migrations for legitimate projects whose `index.ts` only contains `import { withSentry } from "@sentry/cloudflare"` and relies on lib-observability via a re-export. Recommend a one-line README/CHANGELOG note: "the firewall accepts any Sentry-ish marker; downstream dirty-detection still gates writes."

### IN-03: `release: env.SERVICE_NAME` is semantically a service name, not a release identifier

**File:** `add-observability/templates/ts-cloudflare-worker/lib-observability.ts:158`, `add-observability/templates/ts-cloudflare-pages/lib-observability.ts:165`, `add-observability/templates/openrouter-monitor/src/observability/index.ts:158`
**Issue:** Sentry's `release` field is normally a deployable version identifier (git SHA, semver tag, build ID). The helper sets `release: env.SERVICE_NAME ?? SERVICE_DEFAULT`, which makes `release` and a hypothetical "service tag" identical. This matches the existing inline pattern in openrouter-monitor/src/index.ts (which the helper deliberately mirrors), so it's not a regression — but the mismatched semantic means operators who set up Sentry release-tracking (`fetch source-maps for release X`, `regress this on release Y`) get one bucket per service-name, not per deploy. Worth a comment in the helper JSDoc saying "release defaults to SERVICE_NAME for greenfield projects without a release-tracking pipeline; override at the entry-file site for git-SHA-based releases."
**Fix:**
```typescript
/**
 * ...
 * NOTE: `release` defaults to env.SERVICE_NAME because most greenfield
 * scaffolds lack a release-tracking pipeline. For git-SHA-based release
 * tracking, build a custom options object at the entry file instead of
 * calling this helper, e.g.:
 *   release: env.CF_PAGES_COMMIT_SHA ?? env.SERVICE_NAME ?? SERVICE_DEFAULT
 */
```

### IN-04: Multiple `.gitignore` files duplicate `.env.*.local` and other lines without a shared source

**File:** `add-observability/templates/ts-cloudflare-worker/.gitignore`, `add-observability/templates/ts-cloudflare-pages/.gitignore`, `add-observability/templates/ts-supabase-edge/.gitignore`, `add-observability/templates/ts-react-vite/.gitignore`, `add-observability/templates/go-fly-http/.gitignore`
**Issue:** D-08 ships 5 separate `.gitignore` files with overlapping content (`.env`, `.env.local`, `.env.*.local`, `node_modules/`). Per-stack divergence (`.wrangler/`, `supabase/.temp/`, `.fly/`, `dist-ssr/`) is real and justifies separate files. Three of the five include `[ASSUMED]` markers (cf-pages doesn't say ASSUMED but reuses the cf-worker pattern; supabase-edge marks `supabase/.temp/` ASSUMED; go-fly-http marks `.fly/` ASSUMED; ts-react-vite marks the whole file ASSUMED). The `[ASSUMED]` flag is well-documented but operator-confusing — if a downstream `add-observability init` runs against a Vite project, the entire stack's `.gitignore` lands as "assumed" with no follow-up validation step. Worth a SKILL.md or CHANGELOG note saying the `[ASSUMED]` lines were not verified against live Vite/Fly/Supabase projects during Phase 26; operators should sanity-check the file after `init`.
**Fix:** Either (a) run Phase 26 RESEARCH A1/A2/A3 against live reference projects and drop the `[ASSUMED]` flag, or (b) add a Phase 5.x sub-step to `init/INIT.md` that surfaces the `[ASSUMED]` lines for operator review.

### IN-05: TODO/FIXME-equivalent comments in test files reference Wave-numbered plan state

**File:** `add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts:232-243`, `add-observability/templates/ts-cloudflare-pages/lib-observability.test.ts:574-585`, `add-observability/templates/ts-supabase-edge/index.test.ts:188-208`, `add-observability/templates/openrouter-monitor/src/observability/index.test.ts:8-20`
**Issue:** Several comment blocks reference "Wave 0 RED stub — flips GREEN once Plan 02 / Wave 2 lands the real assertion" or "Wave 0 (Plan 26-01): only the D-02a `describe(...)` block exists." If Phase 26 is now landing the GREEN state (per CHANGELOG header "Phase 26 / DEF-3 closure"), these comments describe a historical-RED state that no longer exists in the codebase. They will mislead future readers who assume the test is still in a RED stub state. The cf-worker test at line 244 actually contains a real implementation (not a stub) — so the "RED stub" comment is stale.
**Fix:** Tighten the comment headers to read "D-02a: init() repeated-init determinism contract (Phase 26 / ADR-0034 — landed Wave 2 GREEN per Plan 02). Contract: ..." and drop the "Wave 0 RED stub" language. Keep the ADR + codex-review reference; drop the wave-bookkeeping.

### IN-06: `parse_vitest_counts` regex won't capture summary lines when all tests fail

**File:** `add-observability/templates/run-template-tests.sh:122-134`
**Issue:** The grep at line 126 is `'^\s+Tests\s+[0-9]+ passed'`. When all tests fail, vitest emits `Tests  N failed` without "passed" — so the regex fails to match and both PASSED/FAILED end up "0". The script's success/fail decision uses `$EXIT_CODE` from the vitest run, not the parsed counts — so this only affects what the script *reports*, not what it *decides*. Cosmetic. The "0 tests passed" line in the fail branch is followed by the last 50 lines of vitest output via `tail -50`, so the operator still sees the real failure info.
**Fix:** Update the regex to also match "all failed" summary lines, or just print the raw vitest summary instead of parsing it:
```bash
# Print last 5 lines of the Tests/Test Files summary unconditionally
echo "$OUTPUT" | grep -E '(Tests|Test Files)' | tail -5 || true
```
This is what the success branch already does. Replace the parse_vitest_counts pre-format with the same `grep -E ... | tail -5` in both branches.

### IN-07: The `# Build artifacts (none today, ...)` comment in cf-worker `.gitignore` is speculative

**File:** `add-observability/templates/ts-cloudflare-worker/.gitignore:17`
**Issue:** Comment reads `# Build artifacts (none today, but `wrangler deploy` may emit to .wrangler/dist)` — the parenthetical hedges that `dist/` may not actually be needed for cf-worker. If `wrangler deploy` does not write to `dist/` for the canonical Worker shape, the entry is harmless but redundant; if it does, the comment is misleadingly tentative. Worth a one-line verification against current `wrangler` version behaviour, or drop the parenthetical and just list `dist/` as a future-proofing entry.
**Fix:** Replace with `# Future-proof: some wrangler workflows emit to dist/`.

---

_Reviewed: 2026-06-01T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
