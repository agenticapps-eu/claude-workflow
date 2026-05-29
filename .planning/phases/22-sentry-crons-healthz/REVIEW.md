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
