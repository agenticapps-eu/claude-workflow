# Phase 22 — Stage 1: Spec Compliance Review

**Reviewer:** Stage 1 (spec compliance)
**Date:** 2026-05-29
**Branch:** `feat/sentry-crons-healthz-v1.18.0`
**Commits reviewed:** 27 (`main..HEAD`)
**Verdict:** **PASS WITH ISSUES** (1 LOW — non-blocking documentation drift)

---

## Methodology

1. Enumerated all 27 commits with `git log --oneline main..HEAD` and inspected the full file scope via `git diff --stat`.
2. Ran both contract test suites to confirm green:
   - `migrations/run-tests.sh` → **PASS=178, FAIL=0** ✅
   - `add-observability/templates/run-template-tests.sh all` → **PASS All stacks passed (or pending)** ✅
3. For each of the 8 Goals, 12 Decisions, and 12 Plan Revisions, verified the actual code (not commit messages) using `grep`, file existence checks, and source inspection.
4. Read both binding artifacts in full (CONTEXT.md, PLAN.md REVISIONS section) before validating.

---

## Goals (G1–G8)

### G1 — `withCronMonitor` exported from 4 stacks; react-vite skipped
- **Status:** ✅ PASS
- **Evidence:**
  - `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:133` — `export function withCronMonitor<E extends Record<string, unknown>>(`
  - `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts:133` — `export function withCronMonitor<R>(`
  - `add-observability/templates/ts-supabase-edge/cron-monitor.ts:182` — `export function withCronMonitor(`
  - `add-observability/templates/go-fly-http/cron_monitor.go:225` — `func WithCronMonitor(ctx context.Context, fn func() error, opts ...CronMonitorOption) error`
  - `add-observability/templates/ts-react-vite/` — no `cron-monitor*` or `healthz*` files (verified via `ls | grep -iE "cron|healthz"` empty result).
- **Issues:** None.

### G2 — All v0.5.1 template exports byte-identical (§10.1)
- **Status:** ✅ PASS
- **Evidence:**
  - `git diff --name-only main..HEAD | grep -E "(lib-observability|middleware|_middleware|observability|destinations|^[^/]*index)\.(ts|go)$"` → **empty** (0 matches).
  - All 50 modified files are new files (cron-monitor / healthz-snippet / fixtures / docs) or whitelisted scaffolder files (`SKILL.md` version bumps, `CHANGELOG.md`, `run-template-tests.sh` runner extension only).
  - `git diff main..HEAD -- add-observability/templates/ts-cloudflare-worker/middleware.ts` → 0 lines. Same for pages `_middleware.ts`, supabase `index.ts`, go `middleware.go`.
- **Issues:** None.

### G3 — Cron heartbeats fire in 3 cases, fail-safe in 1
- **Status:** ✅ PASS
- **Evidence:** Per-stack test files contain all 3 required behavioral cases:
  - **ts-cloudflare-worker** (`cron-monitor.test.ts:36,47,61`): happy / throws-rethrows / no-DSN.
  - **ts-cloudflare-pages** (`cron-monitor.test.ts:35,46,60`): same 3 cases.
  - **ts-supabase-edge** (`cron-monitor.test.ts:94,119,145`): same 3 cases (Deno.test).
  - **go-fly-http** (`cron_monitor_test.go:87,126,153`): `TestWithCronMonitorEmitsCheckinsOnHappyPath`, `TestWithCronMonitorEmitsErrorAndReturnsOriginal`, `TestWithCronMonitorNoopsWhenDSNUnset`.
  - Assertion shape confirmed: `captureCheckIn` called with `monitorSlug` + `status:"in_progress"`, then with `checkInId` + `status:"ok"|"error"`.
- **Issues:** None.

### G4 — Slug resolution honors 3-source precedence (explicit > env > auto)
- **Status:** ✅ PASS
- **Evidence:** Each stack has 3 dedicated precedence tests:
  - **Worker** (`cron-monitor.test.ts:73,86,99`): "explicit wins" / "falls back to env" / "auto-derived `${SERVICE_NAME}:${controller.cron}`".
  - **Pages**: same 3 cases — auto-derive is `${SERVICE_NAME}:${handlerName}` per D6.
  - **Supabase-edge** (`cron-monitor.test.ts:169,191,215`): same 3 cases — handler defaults to `"scheduled"`.
  - **Go** (`cron_monitor_test.go:177,196,216`): `TestSlugExplicitOverridesEnvAndAuto`, `TestSlugEnvOverridesAuto`, `TestSlugAutoDerivesFromServiceNameAndCronExpression`.
- **Issues:** None.

### G5 — `healthz-snippet.{ts,go}` ships in 4 stacks with copy-only contract
- **Status:** ✅ PASS
- **Evidence:**
  - 4 healthz snippets exist (worker / pages / supabase-edge / go-fly-http).
  - `grep -l "WARNING" add-observability/templates/*/healthz-snippet.ts add-observability/templates/*/healthz_snippet.go` → 4 matches (G5 + R07).
  - `grep -l "no probes configured" ...` → 4 matches (R06 fail-closed).
  - Per-stack tests exist: `healthz-snippet.test.ts` (3 TS stacks), `healthz_snippet_test.go` (Go). Tests verify 200/503 contract and zero-probes 503.
- **Issues:** None.

### G6 — Migration 0019 adopts new exports with §10.7 consent
- **Status:** ✅ PASS
- **Evidence:**
  - `migrations/0019-sentry-crons-and-healthz.md` exists; frontmatter `from_version: 1.17.0`, `to_version: 1.18.0` ✅.
  - 7 fixture directories under `migrations/test-fixtures/0019/`: `01-fresh-apply`, `02-already-applied`, `03-hand-modified-refuse`, `04-no-scheduled-handlers-project`, `05-multi-module-root`, `06-multi-root-mixed-clean-dirty-refuses-all`, `07-react-vite-only` (5 from PLAN + 2 from R09).
  - `bash migrations/run-tests.sh 2>&1 | tail -1` → **`PASS: 178`** (FAIL=0 — green suite).
  - Apply engine at `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` (724 lines) mirrors 0017's `canonicalize_awk` + `is_known_clean_wrapper` pattern.
- **Issues:** None.

### G7 — Operator runbook published
- **Status:** ✅ PASS
- **Evidence:** `add-observability/uptime-setup-runbook.md` exists (460 lines) with 4 parts:
  - Part 1 — Sentry Crons (line 36)
  - Part 2 — Sentry Uptime (line 182)
  - Part 3 — `policy.md` cross-link (line 261)
  - Part 4 — Security & Public Exposure (line 311) — added per R10.
- **Issues:** None.

### G8 — Version bumps + CHANGELOG + ADR-0028 + green suites
- **Status:** ✅ PASS
- **Evidence:**
  - `skill/SKILL.md:1` → `version: 1.18.0` ✅
  - `add-observability/SKILL.md:1` → `version: 0.6.0` ✅
  - `CHANGELOG.md` has 1 `## [1.18.0]` section ✅
  - `docs/decisions/0028-sentry-crons-healthz-conventions.md` exists (124 lines) ✅
  - Both contract suites green (PASS=178 migrations / All stacks passed templates).
- **Issues:** None.

---

## Decisions (D1–D12)

### D1 — Separate wrapper, not config option
- **Status:** ✅ PASS
- **Evidence:** `cron-monitor.ts` is a NEW sibling file in each of 4 stacks. Confirmed via `git diff main..HEAD -- middleware.ts` → 0 lines for all 4 stacks. `withObservabilityScheduled` signature unchanged.

### D2 — No Axiom mirroring of checkins
- **Status:** ✅ PASS
- **Evidence:** `grep -rn "axiom\|@axiomhq" add-observability/templates/*/cron-monitor.ts add-observability/templates/*/cron_monitor.go` → **0 hits**. Only Sentry packages imported: `cron_monitor.go:31` imports `github.com/getsentry/sentry-go`; TS files import from `@sentry/cloudflare` (worker), `@sentry/node` (pages), `npm:@sentry/deno` (supabase).

### D3 — Slug stable; commit SHA goes to environment/release context, not slug
- **Status:** ✅ PASS
- **Evidence:** `resolveSlug` functions in all 4 stacks reference only:
  - Explicit `config.monitorSlug` arg.
  - Env var `SENTRY_CRON_MONITOR_SLUG_<HANDLER>`.
  - Static auto-derive: `${SERVICE_NAME}:${...}`.
  - No `git`, `SHA`, `process.env.SOMETHING_SHA`, or `os.Getenv("...SHA")` calls. `grep "SHA\|commit\|git\|GIT"` returned only the unrelated `sentry-go` package import (`getsentry/sentry-go`).

### D4 — `/healthz` is NOT wrapped by `withObservability`
- **Status:** ✅ PASS
- **Evidence:** All 4 healthz snippets use raw `Response` / `http.HandlerFunc`. Searches for `import.*middleware|import.*observability|withObservability` returned only **explanatory comments** stating "NOT wrapped by withObservability" — no actual imports. Go snippet has no `observability` import (verified empty result).

### D5a/b/c/d — Per-stack composition
- **Status:** ✅ PASS (with minor doc gap — see below)
- **Evidence:** Each `cron-monitor.{ts,go}` file's header comment explicitly references its decision:
  - Worker (`cron-monitor.ts:7-8`): `// Composes INNERMOST per D5a: withSentry(env)(withObservabilityScheduled(withCronMonitor(handler, {...})))`
  - Supabase-edge (`cron-monitor.ts:5`): `// Per CONTEXT D5b, the Supabase Edge stack composes as: ...`
  - Pages (`cron-monitor.ts:4-14`): explicit D5c statement.
  - Go (`cron_monitor.go:6`): `// Composes INNERMOST per D5d:`
- **Doc gap (LOW):** CONTEXT.md G1 says "Documented per-stack in `add-observability/init/INIT.md` Phase 5 rewrite-shape sections", but `git diff main..HEAD -- add-observability/init/INIT.md` is empty — INIT.md was NOT updated. The decision is honored at the source-comment level (which arguably matters more for operators), and the runbook describes per-stack patterns by example, but the CONTEXT.md promise of INIT.md Phase-5-section updates is unmet. **Non-blocking** because the composition guidance reaches operators via runbook + source comments.

### D6 — Slug resolution 3-source precedence
- **Status:** ✅ PASS (covered by G4)

### D7 — Healthz copy-only, not auto-mounted
- **Status:** ✅ PASS
- **Evidence:** Every healthz snippet has the multi-line WARNING block (R07) AND a "Do NOT import this file" message. `grep -l "Do NOT import\|do not import\|Do not import" ...` returned all 4 files. Migration 0019 does not mount these snippets — they're shipped to the wrapper dir only; operator copies into routes layer.

### D8 — Hand-modified refuse mirrors 0017
- **Status:** ✅ PASS
- **Evidence:** `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`:
  - Line 13 comment: "Same `canonicalize_awk` style-insensitive content-hash canonicaliser"
  - Line 303: `canonicalize_awk()` defined (copied verbatim from 0017)
  - Line 407–409: `is_known_clean_wrapper()` function
  - Line 425–426: `declare -a CLEAN_DIRS=() ... DIRTY_DIRS=()`
  - Line 576–582: all-clean gate per R08 binding.

### D9 — SKILL.md drift hotfix folded as commit 1
- **Status:** ✅ PASS
- **Evidence:** `git log main..HEAD --oneline | tail -1` → `122aafa fix(0018): bump skill/SKILL.md version 1.16.0 → 1.17.0 (PR #52 follow-up)` — confirmed as the oldest commit on the branch.

### D10 — react-vite fully skipped
- **Status:** ✅ PASS
- **Evidence:** `ls add-observability/templates/ts-react-vite/ | grep -iE "cron|healthz"` → empty. Fixture `07-react-vite-only/` verifies the migration recognises "no eligible stacks" and writes no files (exit 0).

### D11 — Multi-cron workers must pass `monitorSlug` explicitly
- **Status:** ✅ PASS
- **Evidence:** `add-observability/uptime-setup-runbook.md:71-87` has an explicit "Multi-cron workers (D11)" callout block with a code example using `SLUG_BY_CRON[controller.cron]`. Cross-reference at line 455.

### D12 — `schedule` + `maxRuntimeSeconds` forwarded as monitorConfig on first checkin
- **Status:** ✅ PASS
- **Evidence:** All 4 stacks implement `buildMonitorConfig()` that returns `undefined` when neither field is set; `monitorConfig` is passed as 2nd arg to `captureCheckIn` ONLY on the `in_progress` checkin. Worker (`cron-monitor.ts:145,151–157`), pages (`cron-monitor.ts:144,150–157`), supabase-edge (`cron-monitor.ts:193,198–199`), go (`cron_monitor.go:108`). Each stack has a dedicated test ("forwards monitorConfig on in_progress, omits on completion") asserting `mock.calls[0][1]` shape AND `mock.calls[1][1]` is undefined. CONTEXT.md's "claimed but dead field" risk is fully resolved.

---

## Plan Revisions (R01–R12)

### R01 — T01 simplification (worker + pages only)
- **Status:** ✅ PASS
- **Evidence:** `run-template-tests.sh` diff shows explicit `substitute_tokens` lines added only inside `test_ts_cloudflare_worker()` and `test_ts_cloudflare_pages()`. Supabase covered by `for f in "$SRC"/*.test.ts` glob (line 474); Go covered by `for f in "$SRC"/*.go` glob (line 553).

### R02 — No existence-gated copy lines
- **Status:** ✅ PASS
- **Evidence:** `grep -nE '\[\[ -f .*substitute_tokens|&&\s*substitute_tokens' run-template-tests.sh` → **0 matches**. T18 commit `47659ec` explicitly removed the temporary gates that landed during RED/GREEN staging.

### R03 — monitorConfig forwarded on `in_progress` only
- **Status:** ✅ PASS
- **Evidence:** Covered jointly with D12. Worker test (`cron-monitor.test.ts:122–130`):
  ```
  expect(vi.mocked(captureCheckIn).mock.calls[0][1]).toEqual({ schedule: {...}, maxRuntime: 240 });
  expect(vi.mocked(captureCheckIn).mock.calls[1][1]).toBeUndefined();
  ```
  Each stack has a "forwards monitorConfig" AND a "omits monitorConfig entirely when unset" test pair.

### R04 — `SENTRY_DEBUG=1` opt-in `console.error`
- **Status:** ✅ PASS
- **Evidence:** `grep -l "SENTRY_DEBUG" add-observability/templates/*/cron-monitor.* add-observability/templates/*/cron_monitor.go` → **4 matches**. Per-stack tests:
  - Worker `cron-monitor.test.ts:152` — "logs swallowed errors when SENTRY_DEBUG=1, silent otherwise"
  - Pages `cron-monitor.test.ts:153` — same
  - Supabase `cron-monitor.test.ts:286` — same
  - Go `cron_monitor_test.go:287` — `TestSentryDebugSurfacesSwallowedCheckinError`

### R05 — Go `captureCheckinFn` returns `*sentry.EventID`
- **Status:** ✅ PASS
- **Evidence:** `cron_monitor.go:108`:
  ```go
  var captureCheckinFn = func(checkIn *sentry.CheckIn, monitorConfig *sentry.MonitorConfig) *sentry.EventID {
  ```
  Lines 19, 102 contain explicit R05 spec-note comments. `safeCaptureCheckin` at line 190 returns `*sentry.EventID` too.

### R06 — Healthz fail-closed on zero probes
- **Status:** ✅ PASS
- **Evidence:** `grep -l "no probes configured" add-observability/templates/*/healthz-snippet.* add-observability/templates/*/healthz_snippet.go` → **4 matches**. Per-stack tests assert 503 + `reason: no probes configured` when no deps wired.

### R07 — Multi-line WARNING block
- **Status:** ✅ PASS
- **Evidence:** Covered by G5. All 4 healthz snippets contain the WARNING block; verified via `grep -l "WARNING" ...` → 4 matches.

### R08 — Migration 0019 2-pass atomic
- **Status:** ✅ PASS
- **Evidence:** `migrate-0019-sentry-crons-and-healthz.sh`:
  - Lines 425–456: Pass 1 classifies into `CLEAN_DIRS` / `DIRTY_DIRS` / `ALREADY_DIRS` / `UNSUPPORTED_DIRS`.
  - Lines 576–582: explicit "all-clean gate (R08 binding)" — exits if any dirty, refuse atomically.
  - Line 675+: Pass 2 — only runs when gate passes.
  - Refuse-side emits `.observability-0019.patch` per clean dir (line 571: `emit_refuse_artifacts_for "$dir" "$stack" "CLEAN-skipped"`).

### R09 — Fixtures 06 + 07 added
- **Status:** ✅ PASS
- **Evidence:** `ls migrations/test-fixtures/0019/` shows all 7 expected fixture dirs including `06-multi-root-mixed-clean-dirty-refuses-all` and `07-react-vite-only`. Both pass in the `PASS=178` test suite.

### R10 — Runbook Part 4 Security
- **Status:** ✅ PASS
- **Evidence:** `add-observability/uptime-setup-runbook.md:311` — `## Part 4 — Security & Public Exposure`. `grep -c "Part 4"` returns 3 (heading + 2 cross-refs).

### R11 — T17 byte-identical via filename allowlist
- **Status:** ✅ PASS
- **Evidence:** No T17-named commit in the branch (consistent with R11 reframing T17 to verification-only). The runner's structural assertion (T18 R12 block at line 615+) enforces export presence, and G2's "no diff on existing wrapper files" check substantiates the allowlist intent.

### R12 — T18 cleanup (existence gates removed + export-presence assertion)
- **Status:** ✅ PASS
- **Evidence:**
  - Commit `47659ec` removes 3 existence-gated healthz-snippet copy blocks (lines 145-150 worker, 263-268 pages, 478-480 supabase per commit message).
  - `run-template-tests.sh:615–640` — "Phase 22 / T18 / R12 — structural assertion: withCronMonitor export presence" block with `grep -q "func WithCronMonitor"` for Go + equivalent for TS stacks.

---

## Summary

- **Goals met:** 8/8 ✅
- **Decisions honored:** 12/12 ✅ (D5 with 1 LOW doc-drift note)
- **Revisions honored:** 12/12 ✅
- **Both contract suites green:**
  - `migrations/run-tests.sh` → `PASS: 178, FAIL: 0`
  - `add-observability/templates/run-template-tests.sh all` → `PASS All stacks passed (or pending)`
- **27 commits reviewed against the actual code (not commit messages).**

### Issues

| # | Severity | Decision | Description | Suggested fix |
|---|---|---|---|---|
| 1 | LOW | D5 | CONTEXT.md G1 promises per-stack composition documented in `add-observability/init/INIT.md` Phase 5 sections, but `init/INIT.md` was not modified on this branch. Per-stack composition IS documented in the cron-monitor source-file header comments (D5a/b/c/d referenced verbatim) and the runbook describes per-stack patterns by example, so operators are not without guidance. The artifact-location promise in CONTEXT.md is unmet, but the spirit is honored. | Either (a) add a short paragraph in each `add-observability/init/INIT.md` Phase 5 stack subsection citing `withCronMonitor` and the D5x composition, or (b) note in CHANGELOG or PR description that the composition reference moved from INIT.md to source-file headers. Non-blocking — can be a separate follow-up commit before merging or deferred to a 1.18.1 doc patch. |

No HIGH or MEDIUM findings. No spec drift on goals, no scope creep on files (every modified file maps to the R11 allowlist), no test gaps (each contract test exercises the claimed behaviour through real mock assertions on `mock.calls[0][1]` etc., not just absence-of-error), no implementation gaps (D12 was specifically de-risked from "claimed but dead field" to live forwarding with dedicated tests).

## Verdict

**PASS WITH ISSUES** — 1 LOW non-blocking documentation drift (D5 per-stack composition reference promised in INIT.md, delivered in source-file headers + runbook). Both contract suites green, all 8 goals shipped, all 12 decisions honored at the behavioural level, all 12 plan revisions executed. Safe to advance to Stage 2 code-quality review without remediation; LOW item can be addressed in a follow-up commit or deferred to a 1.18.1 doc patch at the reviewer/author's discretion.

---

# Stage 2 — Code Quality Review

**Reviewer:** Stage 2 (independent code quality)
**Date:** 2026-05-29
**Branch:** `feat/sentry-crons-healthz-v1.18.0`
**Commits reviewed:** 28 (`main..HEAD`)

## Strengths

- **Comments consistently explain WHY.** Each cron-monitor file's header anchors the impl to a decision ID (D5a/b/c/d, D6, D11, D12) and to the PLAN revisions that shaped it (R02, R03, R04, R05). `buildMonitorConfig` carries a `// Sentry's field name is maxRuntime, not maxRuntimeSeconds — the wrapper exposes the longer/clearer name and renames at the boundary` rationale that a maintainer 6 months from now will read and immediately understand. `resolveSlug` ties D11 to "multi-cron workers MUST pass explicit `monitorSlug`" inline — that's the kind of comment that prevents the next outage.
- **The four impls converge on the same five-step skeleton** (no-DSN gate → resolve slug → build monitorConfig → in_progress → handler/finally → ok-or-error). Reading any one of the four primes you for all four; cognitive load is paid once.
- **Error-handling discipline is uniform.** Every `captureCheckIn` ingress call is in its own try/catch with the same `debugLog` payload shape (`"[withCronMonitor] <phase> checkin failed:"`, err). The Go variant goes one step further with `defer recover()` in `safeCaptureCheckin` — appropriate for the runtime's panic semantics. No swallow point ends without a debug surface.
- **Tests assert behaviour, not mock setup.** Every cron-monitor test inspects either `mock.calls[N][M]` shapes (TS) or the captured `[]capturedCheckin` records (Go) and reads them in observable terms (`status: "in_progress"`, then `status: "ok"` with the same `checkInId`). The D12 forwarding test specifically asserts the 2nd-arg position on call 0 AND its absence on call 1 — that's the contract under test, not the mock plumbing. The R04 test deliberately makes `captureCheckIn` throw and asserts BOTH branches (silent without `SENTRY_DEBUG`, surfaced with it). Hard to write a broken impl that passes these.
- **Migration script mirrors 0017 byte-for-byte where it can.** `canonicalize_awk`, `is_known_clean_wrapper`, the 2-pass classify→gate→apply structure, the `.observability-NNNN.patch` refuse artefacts, and even the helper tone (`info()`/`warn()`) are direct ports. Comment on line 11–16 explicitly names the mirroring so a future reader doesn't reinvent the canonicaliser; line 261–263 of the migration MD reinforces "any future refinement to the canonicaliser should land in 0017 FIRST and be back-ported here". This is excellent debt-prevention discipline.
- **Healthz WARNING blocks are operator-grade.** All four snippets carry the three-step block (copy → adapt → review security) AND the explicit "Do NOT import this file directly". The Go variant uses Go-doc-comment style instead of the Unicode box because Go's `gofmt` would mangle the box — that's a thoughtful per-stack adaptation, not a copy-paste oversight.
- **Test seams in Go are documented.** `captureCheckinFn` and `debugLogFn` both carry "MUST NOT use t.Parallel()" warnings inline. The capture stub in `cron_monitor_test.go` uses `t.Cleanup(func() { captureCheckinFn = prev })` to restore the prior fn — proper test isolation even though tests run serially.
- **Atomicity is real, not vestigial.** Fixture 06 (`06-multi-root-mixed-clean-dirty-refuses-all`) verifies that with 2 clean + 1 dirty wrapper roots, ZERO writes happen by default, AND patches are emitted for ALL THREE roots (so the operator has full context). This is the kind of integration test that catches an "oops, I moved the gate inside the loop" regression.
- **DRY is paid where structural, duplicated where independence buys more.** SLUG_ENV_PREFIX = `"SENTRY_CRON_MONITOR_SLUG_"` appears in 4 files, as does the 3-step `resolveSlug` and the `buildMonitorConfig` shape. The duplication is justifiable: per-stack imports diverge (`@sentry/cloudflare` vs `@sentry/node` vs `npm:@sentry/deno` vs `github.com/getsentry/sentry-go`), the env-access pattern diverges (`env.X` vs `Deno.env.get(X)` vs `os.Getenv(X)`), and the runtime types diverge (`ScheduledController` vs `() => Promise<R>` vs `Request → Response` vs `func() error`). A `_shared/` lib would require a per-stack adapter to forward env access AND the SDK seam, which would re-cost as much as it saved and would violate the "each stack-template wrapper is materializable in isolation" v0.5.x invariant. The decision to duplicate is correct.

## Issues

### Critical (BLOCKING — must fix before PR)

None.

### Important (SHOULD fix before merge)

None.

### Minor (NICE)

- **`add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:46–48`** (and 3 sibling files): `isConfigured` reads `env.SENTRY_DSN` AND asserts `(env.SENTRY_DSN as string).length > 0` in two steps when a single `typeof === "string" && env.SENTRY_DSN.length > 0` would do it without the cast. Cosmetic. Same shape on pages and supabase-edge.
- **`add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:150–156`** (pages: same lines; supabase-edge: 198–201): the ternary `monitorConfig !== undefined ? captureCheckIn({…}, monitorConfig) : captureCheckIn({…})` could be replaced with `captureCheckIn({…}, monitorConfig)` if the test asserted `monitorConfig === undefined` (which is the captured 2nd arg) instead of "the 2nd arg position is omitted". The current code is correct against the test as written, but the test asserts `mock.calls[0][1]` is `undefined` either way (an unsupplied arg and an explicit `undefined` are indistinguishable to `mock.calls[0][1]`). Simplification deferred — the ternary documents the intent ("we are deliberately passing nothing") more clearly than a one-argument call would.
- **`add-observability/templates/ts-supabase-edge/cron-monitor.ts:70–74`**: `_setCaptureCheckInForTest` is exported from the production module. The `@internal` JSDoc tag conveys intent, but a downstream-project's `tsc` won't refuse to import it. Acceptable per the inline rationale ("`deno test` has no `vi.mock` equivalent") and mirrors the existing `_resetForTest` precedent in `index.ts`. A `_internal_seams.ts` companion file would be more disciplined but breaks the materialised-in-isolation invariant. Leave as-is.
- **`templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:39`**: `set -uo pipefail` — note the absence of `-e`. This is style-consistent with `migrate-0017-axiom-destination.sh:30` (also `set -uo pipefail`) but is a deliberate choice: many call sites explicitly check `$?` or use `|| true`. The pattern works because the script is structured around explicit error returns from helper functions, not bash's reflexive exit-on-error. Documenting the choice in a top-of-script comment would help a future maintainer who tries to "fix" it.
- **`templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:391–394`** (`canonical_hash`): creates a tempfile with `mktemp`, writes to it, hashes, then `rm -f`. If the `awk` fails the `|| cp "$f" "$tmp"` fallback still produces a hash but the temp file might leak on script abort between `mktemp` and `rm -f`. No `trap` cleans up. Same shape as 0017 line 305. Low impact — `mktemp` files land under `/tmp` and get OS-swept; adding a global `trap 'rm -f /tmp/0019.*' EXIT` would be cleaner but is not a regression vs 0017.
- **`add-observability/uptime-setup-runbook.md:207`** (Part 2 Step 1 example output): `expected: {"status":"ok","checks":{"kv":true,"serviceBinding":true}}` shows the per-check breakdown by default. Part 4 (line 388-391) acknowledges this and notes the Sentry Uptime monitor's body-match should change to `"status":"ok"` (shallow) after applying Mitigation 1's `?detail=true` gating. The runbook is internally consistent but a junior operator reading Part 2 in isolation would set the body-match to the detailed shape and then break it when they apply Mitigation 1. A one-line forward-reference at line 224 (something like "see Part 4 for production hardening — the shallow form is the right default for public probes") would close the loop. Non-blocking — Part 4 itself is clear.
- **`add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:155, 156`**: the type cast chain `as unknown as string` for `captureCheckIn`'s return appears twice per file × 3 TS files. Sentry's `captureCheckIn` returns `string` in the cloudflare SDK and `string | undefined` in the deno variant; the cast obscures this rather than typing it correctly. A typed thin wrapper `function checkIn(...) : string | undefined { return captureCheckIn(...) as string | undefined; }` would centralise the cast. Low value — the cast is colocated and the comment names what's happening.
- **`add-observability/templates/go-fly-http/cron_monitor.go:172–184`** (`buildCronMonitorConfig`): handles `cfg.schedule == nil && cfg.maxRuntimeSeconds == 0` as the "nothing set" case. A caller who legitimately wants `WithMaxRuntimeSeconds(0)` to forward as MonitorConfig.MaxRuntime=0 cannot do so (the option is silently equivalent to absent). The TS variant has `hasMaxRuntime = config.maxRuntimeSeconds !== undefined` which correctly distinguishes "not set" from "set to 0". Go's zero-value semantics make this hard to fix without an `*int` pointer or a `bool maxRuntimeSet` flag; in practice `maxRuntime=0` is meaningless (a 0-second cron is degenerate). Document the caveat in the `WithMaxRuntimeSeconds` doc comment or accept the asymmetry.
- **`add-observability/templates/go-fly-http/cron_monitor.go:225`** (`func WithCronMonitor(ctx context.Context, ...)`): the `ctx` param is unused (line 226: `_ = ctx`). The comment at line 223–224 explains "accepted for future extension (e.g. tracing the heartbeat under the request span)". This is borderline gold-plating — Go's idiom is to add parameters when needed, not to reserve them. But changing the signature later is a breaking change for downstream callers, so the forward-compat hint is defensible. Acceptable.
- **`migrations/0019-sentry-crons-and-healthz.md:248–252`**: the `[1.18.0]` CHANGELOG section mentions 7 fixtures; the migration MD's "Notes" section also lists 7 fixture names but the parenthetical list includes "06-mixed-clean-dirty-refuses-all" which doesn't match the actual directory name "06-multi-root-mixed-clean-dirty-refuses-all". Cosmetic doc drift; the directory is the source of truth. One-character edit if desired.

## Per-dimension assessment

### 1. Naming + readability
Variable names self-document (`monitorSlug`, `checkInId`, `monitorConfig`, `schedule`, `maxRuntimeSeconds`). Function names are precise (`resolveSlug`, `buildMonitorConfig`, `safeCaptureCheckin`, `is_known_clean_wrapper`, `emit_refuse_artifacts_for`). Comments lean WHY-not-WHAT, and the cron-monitor files' file-level header serves as a per-file decision index. Cognitive load is fine; a maintainer with 30 minutes can read any cron-monitor.ts and have a model of all four.

### 2. DRY
Per-stack duplication is justifiable (per-stack SDK imports, per-stack env access patterns, per-stack runtime types). A `_shared/` lib would force adapter layers that re-cost the savings and break the "materialised in isolation" v0.5.x contract. The bash migration script's `canonicalize_awk` is correctly copied verbatim from 0017 with an explicit "any future refinement should land in 0017 FIRST" comment — a future divergence will be caught at code-review time. Healthz snippets duplicate the WARNING-block + R06 fail-closed pattern across 4 files; same justification.

### 3. Test design
Tests verify behaviour through `mock.calls[N][M]` shape assertions, not just "call count = 2". The D12 forwarding test explicitly asserts both presence on call 0 AND absence on call 1, which is the heart of the contract. The R04 SENTRY_DEBUG test toggles the env var and asserts BOTH branches in the same test (silent absence + surfaced presence) — a single-branch test would be insufficient. Go uses package-level seams (`captureCheckinFn`, `debugLogFn`) with `t.Cleanup` restoration and inline non-parallel constraint warnings. The supabase-edge module-level seam (`_setCaptureCheckInForTest`) is documented as a test-only export and mirrors the existing `_resetForTest` precedent. No test could plausibly pass if the impl were broken in a way that affects the assertion shape.

### 4. Error handling
The swallow pattern is correct: `captureCheckIn` is not in the cron's critical path, so an SDK throw must not crash the handler. The opt-in `SENTRY_DEBUG=1` console surface gives operators a knob without polluting normal stdout. There is no swallow point where a HARD error would be more useful (the alternative — propagating the SDK throw — would crash the cron AND break the in-process error capture path, exactly the failure mode the wrapper protects against). Migration engine's atomic-refuse correctly leaves the project untouched: fixture 06 verifies ZERO writes across all roots when ANY is dirty, AND the dirty wrapper bytes are unchanged. Refuse-side patches land into `.observability-0019.patch` per root (clean and dirty) for the operator's recovery context.

### 5. Migration script quality (bash)
`set -uo pipefail` (consistent with 0017's choice — `-e` deliberately omitted in favour of explicit error returns). All variable expansions in conditional contexts are quoted (`[ -n "$TEMPLATES_DIR" ]`, etc.); the unquoted `$files` in `for f in $files` is intentional word-splitting on a controlled space-separated list of fixed identifiers. `declare -a` not `declare -A` — bash 3.2 compatible (verified: declare -a works under `bash 3.2.57(1)-release`). No `trap` for temp-file cleanup, but the `mktemp` files are short-lived and OS-swept; matches 0017's pattern. The 2-pass atomicity is preserved: PASS 1 classifies all roots, PASS 2 applies only after the all-clean gate (or `--allow-partial`). Fixture 06 is the integration test that catches a regression here. Style is consistent with 0017 (helper-function tone, prose comments, section dividers).

### 6. Healthz snippet quality
The WARNING block is unambiguous and operator-actionable (1. copy, 2. adapt, 3. review security; "Do NOT import this file directly"). The R06 fail-closed path on zero probes is correct, well-tested, and explicitly explained in inline comments. The `?detail=true` runbook example (Part 4 Mitigation 1) is correct: it shows the modified handler returning `body.status` always but `body.checks` only when `detail=true`, preserving the R06 fail-closed shape. The probe defaults are realistic and safe per stack: KV `get("healthz-probe")`, D1 `SELECT 1`, Supabase `from("_healthz_probe").select("*").limit(0)`, Go `*sql.DB.PingContext(ctx)`. The supabase probe table name (`_healthz_probe`) is deliberately implausible as a real table — a missing-table failure returns `error.message: "relation does not exist"` and the probe correctly flips to false (rather than silently passing). The Go upstream probe URL `https://internal/healthz` is a placeholder the operator must adapt — the comment at line 71 names this explicitly.

### 7. Migration MD quality
`migrations/0019-sentry-crons-and-healthz.md` is well-ordered: pre-flight aborts (3 sources) → Step 1 hand-modified detection → Step 1a refuse-path UX → Step 2 atomic apply → Step 3 version bump → Rollback → Verify → Skip cases → Notes. The "operator already ran 0017/0018" path is implicit (migration runner is ordered by id; 0019 runs after 0017/0018 succeed and the version is 1.17.0). The pre-flight workflow-version gate accepts `1.17.*` AND `1.18.0` (for clean re-run) which correctly handles the idempotent path. The CONTEXT G6 promise (no CLAUDE.md observability block rewrite) is honored — the migration MD doesn't reference one, and the engine doesn't touch CLAUDE.md.

### 8. CHANGELOG + ADR clarity
CHANGELOG `[1.18.0]` clearly enumerates: new wrapper, new healthz snippet, new runbook, new migration, ADR. Compatibility section names byte-identical exports, test totals, react-vite no-change. A downstream operator can read just this section and understand what they're adopting and what they're not. ADR-0028 articulates the host-discretion-vs-spec-mandate trade-off explicitly: §10.6/§10.7 satisfaction via "affordances exist", with the alternative ("§10.10 mandate") rejected because it would multiply adapter surface across destinations. The "Revisit if downstream evidence shows projects routinely ship without heartbeating despite the affordance" clause is the right kind of decision-fence: future architects know what evidence would unlock revisiting.

### 9. Security-by-construction
No SENTRY_DSN value is ever logged. Only presence checks (`isConfigured()` / `cronIsConfigured()`) gate on `env.SENTRY_DSN`. The operator-controlled `monitorSlug` does not flow into file paths or console outputs other than the Sentry SDK boundary call — the debug log surfaces `"[withCronMonitor] in_progress checkin failed: <Error>"` (no slug). The healthz default DOES leak topology via the `checks` map (kv, serviceBinding, db, supabase, upstream) — but the runbook Part 4 Mitigation 1 documents the `?detail=true` gating pattern, the snippet WARNING block points at it, the CHANGELOG calls it out, and ADR-0028 references it. The default ships the verbose form by design ("local development" rationale). Acceptable per the runbook's explicit hardening guidance.

### 10. Maintenance signals
File sizes are reasonable: 183–270 lines for cron-monitor.{ts,go}, 129–147 for healthz-snippet.{ts,go}. The migration script is 724 lines but ~50% is comments and section dividers; the actual logic (classify → gate → apply) is compact and mirrors 0017's structure. The bash file is approaching the "should split" threshold for general scripts but bash function dispatch + heredoc canonicaliser + 2-pass classifier + apply engine + summary printer naturally cluster together; splitting would require a multi-file install path that complicates the migration MD's `--templates-dir` contract. Keep as-is for now; revisit if 0020 forces a third migration of this shape.

## Verdict

**PASS** — no critical or important issues. The implementation is well-built across all four stacks, tests verify behaviour rather than mock setup, the migration engine correctly mirrors 0017's atomicity properties and is integration-tested, the runbook is operator-grade, and ADR-0028 documents the trade-off cleanly. The handful of minor items (cosmetic ternaries, `WithMaxRuntimeSeconds(0)` edge, fixture-name doc drift, Part 2 / Part 4 forward-reference) are stylistic or doc polish and do not block the PR. Safe to advance to Task #12 (`/cso` security review) without remediation; minor items can be folded as cleanup commits before PR open if convenient or deferred to a 1.18.1 patch.
