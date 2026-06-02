---
phase: 27-1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum-
verified: 2026-06-02T14:00:00Z
status: passed
score: 9/9 must-haves verified
overrides_applied: 0
re_verification: null
gaps: []
human_verification: []
---

# Phase 27: 1.21.0 Stable Baseline Verification Report

**Phase Goal:** Ship claude-workflow 1.21.0 as the cooled-off, stable baseline that downstream factiv repos (cparx, callbot, fx-signal-agent) upgrade to before the three-repo split. Closes PR #60's deferred WR items, establishes canonical PROJECT.md, refreshes drifted STATE/ROADMAP, and lays split-prep groundwork (boundary audit + ADR) — WITHOUT moving any code.

**Verified:** 2026-06-02T14:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | WR-01: go-test counter at lines 633-634 uses `|| true` (not double-count); four firewall `grep -oE … \|\| echo "0"` lines unchanged | VERIFIED | `grep -c '|| echo "0"' run-template-tests.sh` = 4; all 4 are `grep -oE` lines; `grep -c 'grep -c .* || echo "0"'` = 0; lines 633-634 confirmed `|| true` |
| 2 | WR-02: supabase-edge D-02a test calls `_resetForTest()` inside finally; suite GREEN | VERIFIED | `_resetForTest()` at line 233, directly after `console.log = origLog` at line 232, inside the `finally` block of the D-02a test |
| 3 | WR-03: direct `buildSentryOptions` unit tests in all 3 stacks (cf-worker, cf-pages, openrouter); TRACE_SAMPLE_RATE is baked constant (Blocker-C) | VERIFIED | `describe("buildSentryOptions"` block present in all 3 named files; Test C (baked-constant assertion) present in all 3; no `.not.toBe(0.1)` committed; D-02a block has zero functional calls to `buildSentryOptions` |
| 4 | WR-04: openrouter `src/index.ts` routes options through `buildSentryOptions(env)`; no hardcoded `tracesSampleRate: 0.1` in entry | VERIFIED | `withSentry((env: Env) => buildSentryOptions(env), {...})` confirmed; `grep 'tracesSampleRate: 0.1' src/index.ts` returns empty; import `{ buildSentryOptions } from "./observability"` present |
| 5 | Canonical `.planning/PROJECT.md` exists with all D-05 required sections | VERIFIED | File exists (102 lines); `spec-first`, `migration-driven`, `versioning-tracks-migrations`, `SPLIT-00`, downstreams (cparx, callbot, fx-signal-agent), `baseline tag`, `skill version` all confirmed present |
| 6 | STATE.md + ROADMAP.md drift refreshed: Phase 26 merged (46bb394), stale `/gsd-discuss-phase 26` gone, "does not yet exist" pointer resolved | VERIFIED | `grep 'Phase 27' STATE.md` matches; "does not yet exist" gone; `gsd-discuss-phase 26` gone; `46bb394` in both STATE.md and ROADMAP.md; ROADMAP milestone line 15 shows "shipped 1.20.0; PR #60 merged `46bb394`" |
| 7 | `migrations/run-tests.sh` annotated `# SHARED` / `# WORKFLOW` (audit-only, suite still GREEN); ADR-0035 written (Accepted); SPLIT-01 premise corrected | VERIFIED | 9 `# SHARED` annotations + 20 `# WORKFLOW` annotations confirmed; ADR-0035 exists with Status Accepted, references run-tests.sh, mechanism/policy distinction present; SPLIT-01 has `CORRECTION` blockquote referencing run-tests.sh |
| 8 | SPLIT-00 gate changed to pin-by-tag (v1.21.0 / commit SHA); downstream-evidence rule added | VERIFIED | `grep -qi 'pin-by-tag\|git tag\|v1.21.0' SPLIT-00-PREREQUISITES.md` matches; `grep -qi 'commit SHA\|commit pin' SPLIT-00-PREREQUISITES.md` matches |
| 9 | CHANGELOG `## [1.21.0]` section added; `skill/SKILL.md` STAYS 1.20.0; drift test GREEN (A2 tag-only); v1.21.0 tag intentionally absent (deferred manual action) | VERIFIED | `## [1.21.0]` at CHANGELOG line 9; `## [Unreleased]` preserved above it at line 7; all four WR items referenced; 1.20.0 in section (skill-version distinction); `skill/SKILL.md` version: `1.20.0` (unchanged); drift test `test-skill-md-version-matches-latest-migration-to-version` PASS; no VERSION files; v1.21.0 tag absent (by design — deferred to ship time post-PR-merge) |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `add-observability/templates/run-template-tests.sh` | WR-01 go-test counter fix | VERIFIED | Lines 633-634 use `|| true`; 4 firewall `grep -oE` lines intact |
| `add-observability/templates/ts-supabase-edge/index.test.ts` | WR-02 `_resetForTest()` in finally | VERIFIED | `_resetForTest()` at line 233 inside finally block |
| `add-observability/templates/openrouter-monitor/src/observability/index.test.ts` | WR-03 buildSentryOptions tests | VERIFIED | `describe("buildSentryOptions")` block with Tests A/B/C present |
| `add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts` | WR-03 buildSentryOptions tests | VERIFIED | `describe("buildSentryOptions")` block with Tests A/B/C present |
| `add-observability/templates/ts-cloudflare-pages/lib-observability.test.ts` | WR-03 buildSentryOptions tests | VERIFIED | `describe("buildSentryOptions")` block with Tests A/B/C present |
| `add-observability/templates/openrouter-monitor/src/index.ts` | WR-04 entry using buildSentryOptions(env) | VERIFIED | `withSentry((env: Env) => buildSentryOptions(env), ...)` at line 47; no hardcoded tracesSampleRate |
| `.planning/PROJECT.md` | Canonical product identity (D-05) | VERIFIED | 102 lines; all 7 required sections present |
| `.planning/STATE.md` | Drift-refreshed (Phase 26 merged, Phase 27 position) | VERIFIED | Phase 27 referenced; 46bb394 present; stale lines gone |
| `.planning/ROADMAP.md` | Phase 26 marked complete/merged | VERIFIED | 46bb394 on milestone line; progress table row updated |
| `migrations/run-tests.sh` | # SHARED / # WORKFLOW annotations | VERIFIED | 9 SHARED + 20 WORKFLOW markers; comment-only (0 deletions per git diff) |
| `docs/decisions/0035-shared-extraction-boundaries.md` | ADR-0035 (Status: Accepted) | VERIFIED | Exists; Status Accepted; run-tests.sh referenced; mechanism/policy distinction present |
| `SPLIT-01-agenticapps-shared.md` | gsd-tools.cjs premise correction | VERIFIED | CORRECTION blockquote present; run-tests.sh named as extraction target |
| `SPLIT-00-PREREQUISITES.md` | pin-by-tag gate fix | VERIFIED | pin-by-tag, v1.21.0, commit SHA all present |
| `CHANGELOG.md` | `## [1.21.0]` release section | VERIFIED | Section at line 9; [Unreleased] preserved above; all WR items referenced; 1.20.0 skill-version note present |
| `skill/SKILL.md` | STAYS at version 1.20.0 (A2) | VERIFIED | `version: 1.20.0` confirmed |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `run-template-tests.sh:633-634` | go-test pass/fail reporting | `grep -c '^--- PASS' \|\| true` | WIRED | Pattern confirmed present; no `|| echo "0"` on grep-c lines |
| `openrouter-monitor/src/index.ts` | `buildSentryOptions` | `withSentry((env: Env) => buildSentryOptions(env), ...)` | WIRED | Exact pattern matches; import present |
| `.planning/STATE.md` | `.planning/PROJECT.md` | Project Reference pointer | WIRED | "does not yet exist" parenthetical removed; PROJECT.md resolves |
| `docs/decisions/0035-shared-extraction-boundaries.md` | `migrations/run-tests.sh` annotations | canonical boundary reference for SPLIT-01 Phase C | WIRED | ADR references run-tests.sh annotations by name |
| `CHANGELOG.md ## [1.21.0]` | git tag v1.21.0 | release marker | DEFERRED (by design) | Tag is a manual release action after PR merge to main; absence is intentional per plan specification |

### Data-Flow Trace (Level 4)

Not applicable — this phase is documentation, test, annotation, and a test-file wiring change only. The WR-04 `src/index.ts` change routes an existing runtime call through an existing helper; no new data sources, state variables, or rendering paths are introduced.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Drift test PASSES (SKILL.md 1.20.0 == migration 0021 to_version) | `bash migrations/run-tests.sh 2>&1 \| grep 'test-skill-md-version'` | PASS confirmed | PASS |
| 4 pre-existing baseline failures unchanged (not regressions) | Migration suite output | FAIL: 4 (02/06/10/11 verify-paths — pre-existing baseline) | EXPECTED — documented in phase prompt as pre-existing |
| `describe("buildSentryOptions"` block present in all 3 target test files | `grep -q 'describe("buildSentryOptions"' <file>` | PRESENT × 3 | PASS |
| No deliberately-false assertion committed | `grep -rn '.not.toBe(0.1)' --include='*.test.ts'` | 0 results | PASS |
| WR-04: no hardcoded `tracesSampleRate: 0.1` in openrouter entry | `grep 'tracesSampleRate: 0.1' src/index.ts` | 0 results | PASS |
| All phase commits verified | `git log --oneline <9 commit hashes>` | All 9 commits found in history | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| WR-01 | 27-01 | go-test counter double-count fixed | SATISFIED | Lines 633-634 use `|| true`; firewall lines content-verified |
| WR-02 | 27-01 | supabase-edge D-02a `_resetForTest()` in finally | SATISFIED | Line 233 in index.test.ts |
| WR-03 | 27-02 | buildSentryOptions direct unit tests × 3 stacks | SATISFIED | describe blocks present in all 3 files with A/B/C tests |
| WR-04 | 27-05 | openrouter entry routes through buildSentryOptions(env) | SATISFIED | Line 47 in src/index.ts; import present |
| PROJECT-MD | 27-03 | Canonical .planning/PROJECT.md (D-05) | SATISFIED | 102-line file with all required sections |
| STATE-ROADMAP-DRIFT | 27-03 | STATE.md + ROADMAP.md drift refresh | SATISFIED | All 5 acceptance criteria confirmed |
| SPLIT-PREP-AUDIT | 27-04 | run-tests.sh annotations + ADR-0035 + SPLIT-01 correction | SATISFIED | 9 SHARED + 20 WORKFLOW; ADR-0035 Accepted; CORRECTION note present |
| SPLIT-00-GATE-FIX | 27-04 | SPLIT-00 gate changed to pin-by-tag | SATISFIED | pin-by-tag + commit SHA rule confirmed in SPLIT-00-PREREQUISITES.md |
| CHANGELOG-1210 | 27-06 | CHANGELOG ## [1.21.0] section (A2 tag-only) | SATISFIED | Section present; [Unreleased] above; all WR items; skill-version note |
| RELEASE-TAG | 27-06 | git tag v1.21.0 at ship time (manual) | DEFERRED (by design) | `autonomous: false`; deferred to post-PR-merge; no tag expected during execute-phase |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | No TODO/FIXME/placeholder/stub patterns in phase artifacts | — | — |

**Code Review Findings (from 27-REVIEW.md):**

The review found 0 critical, 1 warning, 2 info-level findings. None block goal achievement:

- **WARNING (review):** openrouter `index.test.ts` Test B hardcodes `"openrouter-monitor"` without a comment clarifying it is not a template token (maintenance trap). Does not affect correctness — the assertion is correct for this non-materialized file.
- **INFO IN-01 (review):** D-02a in cf-worker/cf-pages uses direct `console.log =` reassignment instead of `vi.spyOn`. Tests are GREEN; fragile under concurrent spy activity. Out of scope for Phase 27 (pre-existing pattern).
- **INFO IN-02 (review):** `SPLIT-01-agenticapps-shared.md` Phase B filter-repo command still references the superseded `bin/gsd-tools.cjs` path (not updated to match the CORRECTION blockquote). Phase 27 goal is audit-only; the command is illustrative documentation for a future executor.

None of these are blockers for the phase goal.

### Human Verification Required

None — all success criteria are verifiable programmatically. The v1.21.0 git tag is an intentionally deferred manual release action (not a human verification item; it is a ship-time operational step).

### Gaps Summary

No gaps. All 9 success criteria are verified against the actual codebase. The phase goal — shipping the 1.21.0 stable baseline with WR-01..04 closed, PROJECT.md established, STATE/ROADMAP refreshed, split-prep groundwork laid, and CHANGELOG updated — is fully achieved. The v1.21.0 git tag remains intentionally absent, pending PR merge to main.

---

_Verified: 2026-06-02T14:00:00Z_
_Verifier: Claude (gsd-verifier)_
