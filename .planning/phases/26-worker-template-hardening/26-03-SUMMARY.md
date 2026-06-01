---
phase: 26-worker-template-hardening
plan: 03
subsystem: observability
tags: [harness-pinning, engine-filter, fixture-fix, version-bump, byte-symmetry, drift-test, codex-cross-ai, nyquist-compliant]

# Dependency graph
requires:
  - phase: 25-fix-0019-engine-and-cron-wrappers
    provides: D-21 byte-symmetry contract (token-substituted); migration 0021 baseline (to_version v1.20.0); drift test F4
  - plan: 26-01
    provides: ADR-0034; RED fixture 13; D-02a stubs; W0 RED baseline
  - plan: 26-02
    provides: ENV-PURE buildSentryOptions × 3; D-02a GREEN flip; REDACTED_KEYS additive × 5 stacks; .gitignore × 5
provides:
  - vitest EXACT pin (3.2.4) × 3 heredocs + @sentry/cloudflare TILDE pin (~8.55.0) × 2 — closes F-2
  - DUAL-strategy harness-pin policy comment block — codex HIGH-4 documented
  - _filter_index_ts_requires_co_anchor content-marker firewall — fixture 13 RED→GREEN
  - 0021/04 fixture TS1038 fix + honest fail-fast (exit-0 mask removed)
  - add-observability 0.10.0 release (NO BRACKETS CHANGELOG + UPGRADE NOTE)
  - claude-workflow Phase 26 entry parked in [Unreleased] (D-10a deviated per drift-test invariant)
  - openrouter-monitor REDACTED_KEYS byte-symmetry repair (D-05 follow-up Plan 02 missed)
  - 26-VALIDATION.md nyquist_compliant: true + plan-checker W1 stale-text drift fixes
affects: [next-migration-shipping-phase-will-claim-the-deferred-1.20.1-bump, post-merge-/gsd-verify-work-26, /gsd-review-26]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "DUAL-strategy version pinning: EXACT vs TILDE per dep risk profile (codex HIGH-4 — npm tilde semantics permit >=X.Y.Z <X.(Y+1).0)"
    - "Content-marker firewall: bash grep -qiE inside engine classifier function (Phase 26 CR-D / D-06)"
    - "Canonical TypeScript Console ambient: `interface Console + declare var console: Console` (NOT `declare const` inside `declare global` — TS1038)"
    - "Drift-test invariant precedence over plan instructions: when SKILL.md version equals latest migration's to_version is engine-enforced, version bump deferral to `[Unreleased]` is correct (user-memory: versioning-tracks-migrations)"
    - "TOKEN-SUBSTITUTED byte-symmetry verification via sed substitution into diff <( ... )"
    - "Capture-once Mechanical-1 discipline: full validation suite captured ONCE per stack, asserted from the captured log (no re-runs that could mask flakiness)"

key-files:
  created: []
  modified:
    - add-observability/templates/run-template-tests.sh
    - templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
    - migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts
    - migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/verify.sh
    - add-observability/templates/openrouter-monitor/src/observability/index.ts
    - add-observability/CHANGELOG.md
    - add-observability/SKILL.md
    - CHANGELOG.md
    - .planning/phases/26-worker-template-hardening/26-VALIDATION.md

key-decisions:
  - "vitest pinned EXACT 3.2.4 (codex HIGH-4): tilde was insufficient — `~3.2.4` ≡ >=3.2.4 <3.3.0 still allows the 3.2.5 drift event. Only EXACT blocks it."
  - "@sentry/cloudflare pinned TILDE ~8.55.0: different risk profile (SDK is more stable; patch drift acceptable). D-03b policy comment documents the asymmetry."
  - "ts-react-vite's @sentry/react untouched (uses different package — Risk 4 honored)."
  - "Engine content-marker regex: `observability|lib-observability|withObservability|sentry|agenticapps:observability` case-insensitive (broad `sentry` substring catches all canonical patterns)."
  - "TS1038 canonical pattern: `interface Console + declare var console: Console` (NOT `declare const`)."
  - "Honest fail-fast in 0021/04 verify.sh: removed exit-0 mask; exit 1 with explicit error string when npx absent."
  - "claude-workflow 1.20.1 version bump DEFERRED to [Unreleased] (Rule 4 deviation): drift test enforces SKILL.md == latest migration's to_version; Phase 26 ships no migration (D-04); user-memory rule says engine bugfixes get no version bump."
  - "add-observability 0.10.0 ships normally (independent SemVer track, no migration-coupling test)."
  - "openrouter-monitor REDACTED_KEYS expanded inline (Rule 2 deviation): Plan 02 missed the bundled-resolved variant; Phase 25 D-21 byte-symmetry contract repair."
  - "nyquist_compliant flipped to true after every per-D-XX grep verification passed (codex MED-5)."

patterns-established:
  - "Drift-test as truth source: when migrations/run-tests.sh F4 fails because of a planner-asked version bump, the drift test wins (user-memory: versioning-tracks-migrations)."
  - "Byte-symmetry repair as Rule 2 deviation: D-21 contract is template-pair invariant — when an additive change to the parameterized side (cf-worker meta.yaml) is not mirrored into the bundled-resolved side (openrouter-monitor index.ts), execute the repair inline."
  - "Plan-checker W1 drift fixes via Edit tool: stale text in VALIDATION.md tables and bullets (idempotency → repeated-init determinism; tilde → EXACT) corrected at wave-final, captured as a separate atomic 'docs' commit."

requirements-completed: [D-03, D-03a, D-03b, D-03c, D-06, D-06b, D-07a, D-07b, D-07c, D-10]
requirements-deviated: [D-10a]  # see Deviations section

# Metrics
duration: ~15 min
completed: 2026-06-01
---

# Phase 26 Plan 03: Wave 3 Engine/Harness/Fixture/Versions Summary

**Wave 3 deliverables shipped: vitest EXACT pin (codex HIGH-4) + DUAL-strategy harness-pin policy + engine content-marker firewall (fixture 13 RED→GREEN) + 0021/04 TS1038 fix + honest fail-fast + add-observability 0.10.0 release + claude-workflow Phase 26 entry deferred to [Unreleased] per drift-test invariant + openrouter byte-symmetry repair + plan-checker W1 stale-text fixes + nyquist_compliant flipped. 6 atomic commits land. PASS=190 FAIL=0 across migrations + all 5 template harness stacks GREEN + openrouter env-stable 14/14 GREEN.**

## Performance

- **Duration:** ~15 min (start 2026-06-01T13:30:16Z → completion 2026-06-01T13:45:33Z)
- **Tasks:** 4 (1 harness pinning, 1 engine filter, 1 fixture fix, 1 versioning + wave-final)
- **Files modified:** 9 (5 production + 1 byte-symmetry repair + 3 docs/planning)
- **Atomic commits:** 6 (4 task commits + 2 deviation/release/nyquist commits)

## Codex Review Verdicts Incorporated

| Codex finding | Severity | Disposition | Where landed in Plan 03 |
|---|---|---|---|
| HIGH-4: EXACT vitest pin, not tilde | HIGH | ACCEPT | Commit `991b392`. 3 EXACT `3.2.4` pins land; 0 tilde pins; DUAL-strategy comment block names both operators. |
| MED-5: 26-VALIDATION.md in files_modified + nyquist flipped | MED | ACCEPT | Frontmatter lists VALIDATION.md; nyquist commit `5c063aa` flips `nyquist_compliant: true` after grep suite passes. |
| Mechanical-1: single-capture suite | MECH | ACCEPT | Tasks 2/3 each capture migration suite ONCE (`/tmp/phase26-d06-fixtures.log`, `/tmp/phase26-d07-fixtures.log`). Task 4 wave-final captures fresh per stack (`/tmp/p26-final-*.log`). No mid-task re-runs that could mask flakiness. |
| Plan-checker W1: stale-text drift in VALIDATION.md | MED (plan-checker) | ACCEPT | 4 edits in nyquist commit: D-03 row uses EXACT-pin grep; D-02a × 4 rows use "repeated-init determinism"; Wave 0 Requirements list updated; Wave 0 RED-verification updated. |

## Task Commits

| # | Description | Commit | Files |
|---|---|---|---|
| 1 | vitest EXACT 3.2.4 + @sentry/cloudflare ~8.55.0 + DUAL-strategy comment + D-03c negative | `991b392` | 1 (run-template-tests.sh) |
| 2 | Engine `_filter_index_ts_requires_co_anchor` content-marker firewall — fixture 13 RED→GREEN | `ac00de2` | 1 (migrate-0019-…sh) |
| 3 | 0021/04 fixture TS1038 + honest fail-fast | `f4f3986` | 2 (types.d.ts + verify.sh) |
| 4a | openrouter-monitor REDACTED_KEYS expansion (Rule 2 deviation — Plan 02 missed) | `63e6c63` | 1 (openrouter-monitor index.ts) |
| 4b | add-observability 0.10.0 release + claude-workflow [Unreleased] (D-10a Rule 4 deviation) | `aa8cc46` | 3 (add-observability/CHANGELOG.md + SKILL.md + root CHANGELOG.md) |
| 4c | nyquist_compliant: true + W1 stale-text fixes | `5c063aa` | 1 (26-VALIDATION.md) |

_All commits used `--no-verify` per parallel-executor protocol. Orchestrator validates hooks after wave completes._

## Final Harness Suite Results (Wave-Final Single Capture per Stack)

| Stack | Log file | Test count | Status |
|---|---|---|---|
| ts-cloudflare-worker | `/tmp/p26-final-cfw.log` | 90 passed | GREEN (vitest@3.2.4 EXACT pin resolves clean — no env-block) |
| ts-cloudflare-pages | `/tmp/p26-final-cfp.log` | 75 passed | GREEN |
| ts-supabase-edge | `/tmp/p26-final-se.log` | 57 passed | GREEN (deno test; no npm) |
| ts-react-vite | `/tmp/p26-final-trv.log` | 43 passed | GREEN |
| go-fly-http | `/tmp/p26-final-gfh.log` | 45 passed | GREEN |
| migrations (engine fixtures) | `/tmp/p26-final-migr.log` | **PASS=190 FAIL=0** | GREEN (includes fixture 13 GREEN-flip + fixture 04 still GREEN + drift test PASS) |
| openrouter-monitor (env-stable, codex MED-1) | `/tmp/p26-final-or.log` | 14 passed (2 test files) | GREEN |

**Total tested:** 324 stack tests + 190 migration fixtures = 514 GREEN. Zero FAIL.

## Engine Fixture Suite (Per-Fixture, From /tmp/p26-final-migr.log)

| Fixture | Status | Notes |
|---|---|---|
| 0019/01-fresh-apply | ✓ | unchanged |
| 0019/02-already-applied | ✓ | unchanged |
| 0019/03-hand-modified-refuse | ✓ | unchanged |
| 0019/04-no-scheduled-handlers-project | ✓ | unchanged |
| 0019/05-multi-module-root | ✓ | unchanged |
| 0019/06-multi-root-mixed-clean-dirty-refuses-all | ✓ | unchanged |
| 0019/07-allow-partial-emits-patches | ✓ | unchanged |
| 0019/07-react-vite-only | ✓ | unchanged |
| 0019/08-index-ts-anchored-worker | ✓ | regression check: still GREEN (real wrapper, content matches `observability\|sentry`) |
| 0019/09-index-ts-anchored-pages | ✓ | regression check: still GREEN |
| 0019/11-stray-index-ts-no-co-anchor | ✓ | regression check: still GREEN (rejected by (a) co-anchor BEFORE new (c) check) |
| 0019/12-dist-shaped-anchor-pair | ✓ | regression check: still GREEN (rejected by (b) dist-path BEFORE new (c) check) |
| **0019/13-index-ts-without-observability-content** | **✓** | **GREEN-FLIP from RED. Wave 0 baseline (`/tmp/phase26-wave0-engine-baseline.log`) showed `✗ … verify exit 1`; post-D-06 the engine demotes the vanilla Hono pair to `unknown` → SKIP_UNSUPPORTED → exit 0 → verify GREEN.** |
| 0021/01-fresh-1.19.0-apply | PASS | unchanged |
| 0021/02-callbot-shape-dirty-refuse | PASS | unchanged |
| 0021/03-already-1.20.0-skip | PASS | unchanged |
| **0021/04-callbot-shape-strict-env-typecheck** | **PASS** | **Still GREEN post-TS1038 fix + exit-0 mask removal.** types.d.ts canonical `interface Console + declare var console: Console`; verify.sh honest fail-fast on npx absent. |
| skill-version-matches-latest-migration-to-version | **PASS** | **Drift test GREEN (post-D-10a deviation): skill/SKILL.md v1.20.0 == migration 0021 to_version v1.20.0.** |

## Openrouter Env-Stable Verification (Codex MED-1)

`/tmp/p26-final-or.log`:

```
 RUN  v2.1.9 /Users/donald/Sourcecode/agenticapps/claude-workflow/add-observability/templates/openrouter-monitor

 ✓ src/check-credit.test.ts (13 tests) 41ms
 ✓ src/observability/index.test.ts (1 test) 6ms

 Test Files  2 passed (2)
      Tests  14 passed (14)
   Start at  15:41:08
   Duration  1.16s
```

D-02a determinism test PASS confirmed at env-stable harness (the canonical codex MED-1 binding evidence). REDACTED_KEYS expansion landed without test breakage.

## Supabase-Edge Runner Block Negative-Assertion (D-03c)

```bash
SE_START=$(grep -n "^run_ts_supabase_edge()" add-observability/templates/run-template-tests.sh | head -1 | cut -d: -f1)
SE_END=$(awk -v start="$SE_START" 'NR>start && /^run_go_fly_http\(\)/ {print NR-1; exit}' add-observability/templates/run-template-tests.sh)
# lines 489..577
matches=$(awk -v s="$SE_START" -v e="$SE_END" 'NR>=s && NR<=e' add-observability/templates/run-template-tests.sh | grep -cE "vitest|@sentry/cloudflare")
# matches == 0
```

**PASS.** Supabase-edge runner block (lines 489–577) contains 0 `vitest|@sentry/cloudflare` matches. The block uses `deno test` directly, no npm install heredoc.

## Byte-Symmetry Verification (TOKEN-SUBSTITUTED Equivalence)

```bash
# Literal diff would always fail by design (cf-worker has {{TOKENS}}; openrouter is resolved):
$ diff -q add-observability/templates/ts-cloudflare-worker/lib-observability.ts \
          add-observability/templates/openrouter-monitor/src/observability/index.ts
Files .../ts-cloudflare-worker/lib-observability.ts and .../openrouter-monitor/src/observability/index.ts differ

# TOKEN-SUBSTITUTED equivalence (Wave 2 Deviation 1 + Plan 03 openrouter REDACTED_KEYS repair):
$ diff <(sed 's/{{ENV_VAR_DSN}}/SENTRY_DSN/g; s/{{ENV_VAR_ENV}}/DEPLOY_ENV/g; s/{{ENV_VAR_SERVICE}}/SERVICE_NAME/g; s/{{SERVICE_NAME}}/openrouter-monitor/g; s/{{DESTINATION}}/sentry/g; s/{{DEBUG_SAMPLE_RATE}}/0.1/g; s/{{TRACE_SAMPLE_RATE}}/0.1/g; s/{{REDACTED_KEYS}}/"password","token","api_key","card_number","cvv","ssn","secret","client_secret","refresh_token","access_token","authorization","bearer","cookie","x-api-key"/g' \
    add-observability/templates/ts-cloudflare-worker/lib-observability.ts) \
  add-observability/templates/openrouter-monitor/src/observability/index.ts
# (empty output — byte-symmetry holds post-repair)
```

**PASS.** Phase 25 D-21 byte-symmetry contract honored under TOKEN-SUBSTITUTED interpretation. Pre-repair the substituted diff showed line 68 diverging (openrouter at 10 entries, cf-worker resolves to 14); commit `63e6c63` brought openrouter to 14 entries inline.

## Per-D-XX Grep Verification Map

| Decision | Grep | Result |
|---|---|---|
| D-01 export cf-worker | `grep -q "^export function buildSentryOptions" cf-worker/lib-observability.ts` | ✓ |
| D-01 export cf-pages | same | ✓ |
| D-01 export openrouter | same | ✓ |
| D-01b negative supabase-edge | `! grep -q "export function buildSentryOptions" supabase-edge/index.ts` | ✓ |
| D-01b negative react-vite | `! grep -rq "export function buildSentryOptions" ts-react-vite/` | ✓ |
| codex HIGH-2 env-pure | `grep -E "environment:\s*env\." ... \| wc -l` → 3 | ✓ (3) |
| codex HIGH-3 no _setTestEnv | `! grep -rq "export function _setTestEnv" add-observability/templates/` | ✓ |
| D-01a env-additions × 3 | `grep -l "^## Sentry integration" ... \| wc -l` → 3 | ✓ (3) |
| D-02 ADR file | `test -f docs/decisions/0034-…md` | ✓ |
| D-02 ADR initialized | `grep -q "initialized" docs/decisions/0034-…md` | ✓ |
| D-02 ADR _testEnv | `grep -q "_testEnv" docs/decisions/0034-…md` | ✓ |
| D-02 ADR isolate-reuse | `grep -qE "isolate.{0,20}reuse\|persists across requests"` | ✓ |
| D-02 ADR determinism | `grep -qE "repeated-init determinism\|deterministic"` | ✓ |
| **codex HIGH-4 vitest EXACT** | `grep -c '"vitest": "3\.2\.4"' run-template-tests.sh` → 3 | ✓ (3) |
| **codex HIGH-4 tilde negative** | `grep -c '"vitest": "~3\.2\.4"' run-template-tests.sh` → 0 | ✓ (0) |
| D-03a sentry tilde × 2 | `grep -c '"@sentry/cloudflare": "~8\.55\.0"'` → 2 | ✓ (2) |
| D-03b DUAL-strategy comment | `grep -q "Harness pins — re-bump deliberately"` AND `grep -q "DUAL strategy"` | ✓ |
| **D-03c supabase-edge negative** | line-range computation + grep count → 0 | ✓ (0 matches in lines 489-577) |
| D-05 (5 stacks meta.yaml) | `grep -l "authorization" templates/*/meta.yaml \| wc -l` → 5 | ✓ (5) |
| D-05 additive preservation | `grep -l "card_number" templates/*/meta.yaml \| wc -l` → 5 | ✓ (5) |
| D-05b (5 stacks policy) | `grep -l "authorization" templates/*/policy.md.template \| wc -l` → 5 | ✓ (5) |
| **D-06 engine CR-D marker** | `grep -q "Phase 26 CR-D" templates/.claude/scripts/migrate-0019-…sh` | ✓ |
| **D-06 fixture 13 GREEN** | `grep -qE "✓.*13-index-ts-without-observability-content" /tmp/p26-final-migr.log` | ✓ |
| **D-07 fixture 04 GREEN** | `grep -qE "PASS 04-callbot-shape-strict-env-typecheck" /tmp/p26-final-migr.log` (Plan 03 Deviation: 0021 dispatcher uses `PASS`, not `✓`) | ✓ |
| **D-07a TS1038 removed** | `! grep -q "declare const console" types.d.ts` | ✓ |
| **D-07a canonical pattern** | `grep -q "interface Console" types.d.ts` AND `grep -q "declare var console: Console" types.d.ts` | ✓ |
| **D-07b exit-0 removed** | `grep -c "^[[:space:]]*exit 0$" verify.sh` → 0 (Plan 03 Deviation: loose `exit 0` matches 2 comments — precise anchor form used) | ✓ (0) |
| **D-07b honest fail string** | `grep -q "fixture 0021/04 FAIL — npx required"` | ✓ |
| D-08 .gitignore × 6 | `find templates -maxdepth 2 -name .gitignore \| wc -l` → 6 | ✓ (6) |
| **D-10 add-observability NO BRACKETS** | `grep -qE "^## 0\.10\.0 — 2026-06-01" add-observability/CHANGELOG.md` | ✓ |
| D-10 NOT brackets | `! grep -qE "^## \[0\.10\.0\]" add-observability/CHANGELOG.md` | ✓ |
| D-10 UPGRADE NOTE | `grep -q "UPGRADE NOTE" add-observability/CHANGELOG.md` | ✓ |
| D-10 codex mention | `grep -q "codex" add-observability/CHANGELOG.md` | ✓ |
| D-10 add-observability/SKILL.md 0.10.0 | `grep -q "^version: 0.10.0" add-observability/SKILL.md` | ✓ |
| **D-10a [Unreleased] (DEVIATED)** | `grep -qE "^## \[Unreleased\] — Phase 26" CHANGELOG.md` | ✓ |
| **D-10a skill/SKILL.md preserved** | `grep -q "^version: 1.20.0" skill/SKILL.md` AND `! grep -q "^version: 1.20.1" skill/SKILL.md` | ✓ |
| **codex MED-5 nyquist** | `grep -q "nyquist_compliant: true" 26-VALIDATION.md` | ✓ |
| **plan-checker W1-1 EXACT-pin** | `grep -q '"vitest": "3.2.4"' 26-VALIDATION.md` | ✓ |
| **plan-checker W1-1 no tilde** | `! grep -q "~3.2.4" 26-VALIDATION.md` (only EXACT-pin grep + sentry tilde remain) | (sentry ~8.55.0 still present — separate row) |
| **plan-checker W1-2/3/4 terminology** | `grep -q "repeated-init determinism" 26-VALIDATION.md` AND `! grep -qE "D-02a.*idempotency\|idempotency.*D-02a"` | ✓ |

## CHANGELOG Format Verification

```bash
$ head -10 add-observability/CHANGELOG.md
# add-observability — CHANGELOG

All notable changes to the `add-observability` skill. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Versioning: this skill ships an independent SemVer track from `claude-workflow`. Minor bumps reflect observable downstream behaviour changes in scaffolded templates.

## 0.10.0 — 2026-06-01     # <-- NO BRACKETS (codex-required format for this file)

Worker-template hardening …

$ head -10 CHANGELOG.md
# Changelog

All notable changes to the AgenticApps Claude Workflow scaffolder are
documented here. The format follows [Keep a Changelog](https://keepachangelog.com/),
and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased] — Phase 26 engine + harness + fixture hardening (2026-06-01)     # <-- BRACKETS (Plan 03 Deviation: parked here per drift-test invariant; 1.20.1 deferred)
```

## Version-Bump Audit

| File | Before | After | Notes |
|---|---|---|---|
| `add-observability/SKILL.md` | `version: 0.9.0` | `version: 0.10.0` | Per plan (no constraint — independent SemVer track) |
| `add-observability/CHANGELOG.md` | (head: `## 0.9.0 — 2026-05-31`) | (head: `## 0.10.0 — 2026-06-01`, NO BRACKETS) | Per plan |
| `skill/SKILL.md` | `version: 1.20.0` | `version: 1.20.0` (**UNCHANGED — Rule 4 deviation**) | Drift test (F4) requires SKILL.md == latest migration to_version; migration 0021 to_version v1.20.0; Phase 26 ships NO new migration (D-04). User-memory rule. |
| `CHANGELOG.md` (root) | (head: `## [Unreleased]` then `## [1.20.0]`) | (head: `## [Unreleased] — Phase 26 …` then `## [1.20.0]`) | Entry parked in `[Unreleased]` with versioning note; will move out when next migration-shipping phase assigns a version. |

## Phase 26 Close-Out Checklist

- **DEF-1** (TRACE_SAMPLE_RATE via env-pure helper, codex HIGH-2) — closed in Plan 02; verified at Wave 3 grep suite ✓
- **DEF-2** (REDACTED_KEYS expansion) — closed in Plan 02 (5 add-observability templates) + Plan 03 (openrouter byte-symmetry repair via commit `63e6c63`) ✓
- **DEF-3** (singleton invariant, codex HIGH-1 corrected ADR) — closed via ADR-0034 + D-02a tests in Plans 01/02 ✓
- **F-2** (harness drift defense, codex HIGH-4 EXACT pin) — closed in Plan 03 Task 1 (commit `991b392`) ✓
- **CR-D** (engine false-positive, fixture 13 GREEN with codex MED-2 SC-5 evidence) — closed in Plan 03 Task 2 (commit `ac00de2`) ✓
- **CR-E** (fixture TS1038 + exit-0 mask) — closed in Plan 03 Task 3 (commit `f4f3986`) ✓
- **.gitignore extended to 5 new stacks** — closed in Plan 02 ✓
- **Versions bumped** — add-observability 0.10.0 ✓; claude-workflow deferred to `[Unreleased]` ✓ (Rule 4 deviation, see below)
- **26-VALIDATION.md nyquist_compliant: true (codex MED-5)** — closed in Plan 03 commit `5c063aa` ✓
- **Plan-checker W1 stale-text drift fixes** — closed in same commit ✓

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 4 - Architectural] D-10a version bump deferred to `[Unreleased]` per drift-test invariant**

- **Found during:** Task 4 Step 5 — full migration suite captured `FAIL: SKILL.md at v1.20.1 but migration 0021 declares to_version: v1.20.0` from the `test-skill-md-version-matches-latest-migration-to-version` test (run-tests.sh F4 block at lines 2210-2232).
- **Issue:** Plan 03 D-10a asked for `skill/SKILL.md` 1.20.0 → 1.20.1 and a root `CHANGELOG.md` `[1.20.1]` entry. But the drift test enforces `skill/SKILL.md` version == the latest migration's `to_version`. Migration 0021's `to_version: v1.20.0` is the chain head. Plan 26-03 D-04 decided NO new migration 0022 (correctly — engine bugfix to existing migration is a template-surface change, not a migration). Therefore the plan's D-10a is INTERNALLY INCONSISTENT with the existing engine-enforced invariant. The user memory rule "versioning-tracks-migrations: engine bugfixes to an existing migration get no version bump" describes exactly this case.
- **Fix:** Reverted `skill/SKILL.md` to v1.20.0. Rewrote root `CHANGELOG.md` Phase 26 entry to live under `## [Unreleased] — Phase 26 engine + harness + fixture hardening (2026-06-01)` with a prominent "Versioning note" explaining the deferral and citing the user-memory rule. The entry will move out of `[Unreleased]` when the next migration-shipping phase assigns it a concrete version. add-observability 0.10.0 still ships (independent SemVer track, no migration-coupling test).
- **Files modified:** `skill/SKILL.md`, `CHANGELOG.md`
- **Verification:** `bash migrations/run-tests.sh` post-fix → `PASS=190 FAIL=0` (drift test GREEN). `grep -q "^version: 1.20.0" skill/SKILL.md && grep -qE "^## \[Unreleased\] — Phase 26" CHANGELOG.md` exits 0.
- **Committed in:** `aa8cc46` (release commit — combined with add-observability 0.10.0 ship).
- **Rationale (judgment per user memory "prefers-judgment-over-asking"):** The drift test is the authoritative source of truth for the rule. The plan-checker missed the inconsistency; honored at execution time per CLAUDE.md precedence rule.

**2. [Rule 2 - Missing Critical] openrouter-monitor REDACTED_KEYS expansion — byte-symmetry repair**

- **Found during:** Task 4 Step 5 — wave-final byte-symmetry verification (TOKEN-SUBSTITUTED diff per Wave 2 Deviation 1) showed line 68 diverging: cf-worker (post-token-substitution) had 14 entries, openrouter's resolved literal had only 10.
- **Issue:** Plan 02 D-05 added 4 entries (`authorization, bearer, cookie, x-api-key`) to the 5 add-observability template meta.yaml + policy.md.template surfaces. But the openrouter-monitor bundled-resolved variant in `src/observability/index.ts` was not updated — Plan 02's `key-files.modified` listed openrouter-monitor's index.ts as modified (only for the `buildSentryOptions` helper, not REDACTED_KEYS). Phase 25 D-21 byte-symmetry contract requires the cf-worker template and the openrouter resolved variant to be TOKEN-SUBSTITUTED equivalent. Without the repair, Plan 03's wave-final byte-symmetry gate would fail.
- **Fix:** Updated `add-observability/templates/openrouter-monitor/src/observability/index.ts` line 68 from the 10-entry literal to the 14-entry literal matching the new generator output.
- **Files modified:** `add-observability/templates/openrouter-monitor/src/observability/index.ts`
- **Verification:** `diff <(sed substitution) ... ` → empty (byte-symmetry holds post-repair). openrouter vitest re-run: 14/14 tests passed.
- **Committed in:** `63e6c63` (separate Rule 2 commit so the diff is reviewable).

**3. [Rule 1 - Bug] Plan acceptance grep `^[[:space:]]*exit 0$` not `exit 0` (substring matches comments)**

- **Found during:** Plan-checker W1 stale-text review during VALIDATION.md update.
- **Issue:** Plan 03 Task 3 acceptance criterion used `grep -c "exit 0" verify.sh` → 0 in some forms. The 0021/04 `verify.sh` contains 2 `exit 0` substrings in COMMENTS (lines 6 and 74: "expect exit 0 — END-TO-END SC5 GREEN"). The loose substring grep returns 2 (FALSE FAIL) even though the actual statement was removed. The precise anchor form `^[[:space:]]*exit 0$` returns 0 (TRUE PASS).
- **Fix:** D-07b row in VALIDATION.md amended to specify the precise anchor form.
- **Files modified:** `.planning/phases/26-worker-template-hardening/26-VALIDATION.md` (D-07b row).
- **Verification:** `grep -c "^[[:space:]]*exit 0$" verify.sh` → 0 (PASS).
- **Committed in:** `5c063aa` (nyquist commit).

**4. [Rule 1 - Bug] 0021 dispatcher uses `PASS` prefix, not `✓` (D-07 fixture green check)**

- **Found during:** Task 3 verification grep against `/tmp/phase26-d07-fixtures.log`.
- **Issue:** Plan 03 Task 3 acceptance criterion used `grep -qE "✓.*04-callbot-shape-strict-env-typecheck" /tmp/phase26-d07-fixtures.log`. But the 0021 fixture dispatcher (a separate runner within migrations/run-tests.sh) emits output like `PASS 04-callbot-shape-strict-env-typecheck`, NOT `✓ 04-...`. Only the 0019 fixture dispatcher uses `✓`. A `✓.*04-...` regex against the actual log would return FALSE-FAIL despite fixture 04 being GREEN.
- **Fix:** D-07 fixture green row in VALIDATION.md amended to use `PASS 04-callbot-shape-strict-env-typecheck` regex. Functional contract (fixture 04 still GREEN) verified independently via log inspection.
- **Files modified:** `.planning/phases/26-worker-template-hardening/26-VALIDATION.md` (D-07 fixture green row).
- **Verification:** `grep -qE "PASS 04-callbot-shape-strict-env-typecheck" /tmp/p26-final-migr.log` → exit 0.
- **Committed in:** `5c063aa` (nyquist commit).

**5. [Rule 1 - Bug] Literal `diff -q` byte-symmetry check is structurally impossible (Wave 2 Deviation 1 carry-forward)**

- **Found during:** Task 4 Step 5 wave-final gate.
- **Issue:** Plan 03 Task 4 Step 5 wave-final assertion list includes `diff -q add-observability/templates/ts-cloudflare-worker/lib-observability.ts add-observability/templates/openrouter-monitor/src/observability/index.ts` and `<verify><automated>` includes the same. As Wave 2 Deviation 1 documented: cf-worker uses `{{TOKEN}}` placeholders; openrouter has them resolved. The literal `diff -q` has NEVER passed and CANNOT pass by construction.
- **Fix:** Applied TOKEN-SUBSTITUTED equivalence interpretation. The substituted-diff is empty (post-deviation 2 byte-symmetry repair). Recorded in VALIDATION.md D-01c row note.
- **Files modified:** `.planning/phases/26-worker-template-hardening/26-VALIDATION.md` (D-01c row).
- **Committed in:** `5c063aa` (nyquist commit).

### Plan-Checker W1 Stale-Text Drift Fixes (per Task 4 Step 6)

All four edits landed in commit `5c063aa`:

1. D-03 row command: `'"vitest": "~3.2.4"' → 3` → `'"vitest": "3.2.4"' → 3 AND '"vitest": "~3.2.4"' → 0`
2. D-02a × 4 rows: `idempotency` → `repeated-init determinism`
3. Wave 0 Requirements list: `D-02 singleton idempotency` → `D-02 singleton repeated-init determinism`
4. Wave 0 RED-verification list: `idempotency test fails` → `repeated-init determinism test fails`

---

**Total deviations:** 5 (1 Rule 4 architectural, 1 Rule 2 missing-critical byte-symmetry repair, 3 Rule 1 literal-template false-FAIL traps).

**Impact on plan:** No scope creep. Deviation 1 (D-10a) is the only material policy change — defers the claude-workflow version bump to the next migration-shipping phase. Deviation 2 (openrouter byte-symmetry repair) is a Plan 02 follow-up that this plan caught at wave-final. Deviations 3-5 are literal-template trap corrections consistent with Wave 1/2's pattern; no fixture or test materially changed. All deviations have been recorded in VALIDATION.md row notes and the commit messages so the trail is fully auditable.

## Codex Cross-AI Review Confirmation

Per memory note "/gsd-review non-skippable", the second `/gsd-review` pass (after Plan 03 corrections — codex HIGH-4, MED-5, Mechanical-1) is still required post-merge. Plan 03 incorporated all surfaced codex corrections:

- HIGH-4 EXACT vitest pin ✓ (3 sites; 0 tilde sites)
- MED-5 26-VALIDATION.md in files_modified + nyquist flipped ✓
- Mechanical-1 single-capture suite ✓ (Tasks 2/3 captured ONCE; Task 4 wave-final fresh per-stack)
- W1 stale-text drift fixes ✓ (4 edits in VALIDATION.md)

Run `/gsd-review 26` to confirm the corrections one more time.

## Issues Encountered

- **PreToolUse:Edit hook reminders fired on already-applied edits.** Same pattern as Plans 01/02. Each Edit succeeded; the runtime emitted READ-BEFORE-EDIT reminders against files already in context. Continued without blocking.
- **vitest@3.2.4 EXACT pin resolves clean.** No env-block during cf-worker/cf-pages harness runs (the prior Phase 25 audit-time `vitest@3.2.5 → vite-node@3.2.5` drift event is now blocked by construction).
- **Drift test fail-then-fix loop.** First wave-final capture (before D-10a deviation) surfaced the drift-test FAIL, prompting the Rule 4 architectural decision. Reset `skill/SKILL.md` to 1.20.0, refactored root CHANGELOG to `[Unreleased]`, re-ran suite — all GREEN. Captured as the canonical Mechanical-1 evidence.

## User Setup Required

None. Phase 26 implementation complete with no operator-facing actions required. The Phase 26 entry in root CHANGELOG `[Unreleased]` will move to a concrete version when the next migration-shipping phase assigns one.

## Next Phase Readiness

**Phase 26 implementation complete.** Recommended next steps:

1. `/gsd-verify-work 26` — verifier confirms every D-XX is satisfied per VALIDATION.md.
2. `/gsd-review 26` — codex cross-AI review #2 (non-skippable per memory). Confirms HIGH-4, MED-5, Mechanical-1 corrections landed AND the D-10a deviation is acceptable.
3. PR open against main. Manual review item from Validation Sign-Off (the only unchecked bullet): manual review of ADR-0034 narrative, env-additions.md snippet quality, CHANGELOG UPGRADE NOTE clarity, .gitignore provenance headers.
4. Post-merge: the next migration-shipping phase claims the deferred Phase 26 changes by assigning a version (e.g., 1.21.0 when a fresh migration ships, or 1.20.1 only if a migration 0022 is scoped to encapsulate the engine D-06 narrowing — D-04 says NO, but a future phase may revisit).

**Known follow-ups (carry forward, not Plan 03 scope):**

- `add-observability/templates/openrouter-monitor/package-lock.json` remains untracked. Phase 24 / Plan 26-01 Deviation #5 flag still stands. A future cleanup pass should commit it.
- `.claude/` directory + `AGENTS.md` + `CLAUDE.md` + `FIX-0017-ENGINE.md` are stale untracked session noise (also flagged in STATE.md). Out of scope for Phase 26.

## Threat Model Coverage

| Threat ID | Disposition | Status |
|---|---|---|
| T-26-T1 (REDACTED_KEYS lag) | accept | Honoured — UPGRADE NOTE in `add-observability/CHANGELOG.md` 0.10.0 entry. |
| T-26-T2 (D-06 regex over-filtering) | mitigate | Honoured — fixtures 08/09/11/12 still GREEN post-Plan 03 D-06; fixture 13 GREEN-flip; broad `sentry` substring captures all canonical patterns. |
| T-26-T3 (pin drift) | mitigate | Honoured — vitest EXACT 3.2.4 blocks 3.2.5; @sentry/cloudflare tilde permits patch only. |
| T-26-T3c (pins leak into supabase-edge) | mitigate | Honoured — D-03c negative assertion: 0 matches in lines 489-577. |
| T-26-T5 (TS1038 fix exposes other errors) | mitigate | Honoured — fixture 04 still PASS post-fix; no new TS errors surface. |
| T-26-T9 (Version-bump comms drift) | mitigate | Honoured — both CHANGELOGs enumerate D-XX with codex corrections; D-10a deviation explicitly documented. |
| T-26-T13 (files_modified missing VALIDATION.md) | mitigate | Honoured — VALIDATION.md in files_modified frontmatter; landed in nyquist commit. |
| T-26-T14 (multi-rerun masks flakiness) | mitigate | Honoured — Tasks 2/3 capture-once; Task 4 wave-final fresh capture; no mid-task re-runs. |

All eight threats at LOW severity. Phase-wide ASVS L1 block-on-high: zero HIGH threats across all 3 plans.

---

## Self-Check: PASSED

**Files modified (verified):**
- FOUND: add-observability/templates/run-template-tests.sh
- FOUND: templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
- FOUND: migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts
- FOUND: migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/verify.sh
- FOUND: add-observability/templates/openrouter-monitor/src/observability/index.ts
- FOUND: add-observability/CHANGELOG.md
- FOUND: add-observability/SKILL.md
- FOUND: CHANGELOG.md
- FOUND: .planning/phases/26-worker-template-hardening/26-VALIDATION.md

**Commits (verified):**
- FOUND: 991b392 fix(26-03,harness): pin vitest EXACT 3.2.4 + @sentry/cloudflare ~8.55.0 + DUAL-strategy policy (D-03, D-03a, D-03b, D-03c)
- FOUND: ac00de2 fix(26-03,engine): _filter_index_ts_requires_co_anchor content-marker firewall — GREEN-flip fixture 13 (D-06, CR-D)
- FOUND: f4f3986 fix(26-03,fixture): 0021/04 TS1038 + honest fail-fast on npx absent (D-07a, D-07b, CR-E)
- FOUND: 63e6c63 fix(26-03,obs): openrouter-monitor REDACTED_KEYS expansion — byte-symmetry repair (D-05 follow-up; Phase 25 D-21)
- FOUND: aa8cc46 release(26-03): add-observability 0.10.0 + claude-workflow Phase 26 entry in [Unreleased] (D-10, D-10a deviated)
- FOUND: 5c063aa docs(26-03): mark nyquist_compliant + plan-checker W1 fixes in 26-VALIDATION.md (codex MED-5)

---
*Phase: 26-worker-template-hardening*
*Plan: 03*
*Completed: 2026-06-01*
