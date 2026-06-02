---
phase: 28-split-01-agenticapps-shared
verified: 2026-06-02T18:41:20Z
status: passed
score: 9/9 must-haves verified
overrides_applied: 0
---

# Phase 28: SPLIT-01 agenticapps-shared Verification Report

**Phase Goal:** Carve the SHARED migration infrastructure (generic runner/harness/helpers + drift-test RUNNER mechanism + extract_to + preflight) out of claude-workflow's migrations/run-tests.sh into the new repo agenticapps-shared, and wire claude-workflow to consume it as a git submodule at vendor/agenticapps-shared. After this phase, the migration suite baseline PASS=186 FAIL=4 must be preserved EXACTLY with the shared lib sourced from the submodule.
**Verified:** 2026-06-02T18:41:20Z
**Status:** passed
**Re-verification:** No — initial verification
**Merge:** Squash-merged via PR #65, commit aa1d60f

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | migrations/run-tests.sh sources the four shared libs from vendor/agenticapps-shared/migrations/lib via BASH_SOURCE-relative path | VERIFIED | Lines 35-66: `_src="${BASH_SOURCE[0]}"`, `_SHARED_LIB="$_SCRIPT_DIR/../vendor/agenticapps-shared/migrations/lib"`, `source "$_SHARED_LIB/helpers.sh"` etc. (all four sourced) |
| 2 | setup_fixture is a WORKFLOW wrapper calling shared extract_to (A1); ADR-0035 amended | VERIFIED | setup_fixture() body at line 111 calls `extract_to` (sourced from fixture-runner.sh); ADR-0035 line 86 lists setup_fixture in WORKFLOW set with A1 rationale; amendment section at line 129; SHARED set contains no setup_fixture row |
| 3 | install.sh advances the submodule when .gitmodules + .git exist (A3) | VERIFIED | install.sh line 30: guards on `.gitmodules` AND (`.git` dir or file); runs `submodule sync --recursive && submodule update --init --recursive`; no VERSION-missing guard (A3). Non-git tarball guard (post-review hardening) also present |
| 4 | HARD GATE: bash migrations/run-tests.sh prints PASS=186 FAIL=4 exactly with drift test PASSING | VERIFIED | Ran live: suite output ends `PASS: 186 / FAIL: 4`; drift test line: `PASS: test-skill-md-version-matches-latest-migration-to-version` |
| 5 | .gitmodules pins vendor/agenticapps-shared over canonical HTTPS; gitlink SHA == 1f5d543 | VERIFIED | .gitmodules URL: `https://github.com/agenticapps-eu/agenticapps-shared`; `git ls-tree HEAD vendor/agenticapps-shared` → `1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4`; matches 28-02 recorded release SHA exactly |
| 6 | agenticapps-shared has its own GREEN standalone suite (tests/run-tests.sh, tag v1.0.0) | VERIFIED | `bash tests/run-tests.sh` → PASS: 12 FAIL: 0 SKIP: 0; `git describe --tags --exact-match HEAD` → v1.0.0; HEAD SHA = 1f5d543 |
| 7 | Four shared lib files exist with correct carved functions and no SHARED boundary violations | VERIFIED | helpers.sh: assert_check, run_check, _runtests_do_cleanup, reset_counters, idempotency guard; fixture-runner.sh: extract_to ONLY (no setup_fixture, no 1.3.0, no workflow paths); preflight.sh: run_preflight_verify_paths parameterized, STRICT_PREFLIGHT:-0, no REPO_ROOT; drift-test.sh: run_drift_test, no PASS/FAIL counter mutation. No obs/GSD leakage. |
| 8 | run-tests.sh retains all WORKFLOW per-migration test bodies and the drift POLICY wrapper | VERIFIED | test_migration_0001 at line 142, test_migration_0021 at line 2066; drift policy wrapper at line 2134-2141 (`if run_drift_test ... then PASS++ else FAIL++`); SHARED function bodies (extract_to, run_check, assert_check, _runtests_do_cleanup) removed |
| 9 | CHANGELOG and ADR-0035 amendment are committed (SC-7/SC-8) | VERIFIED | CHANGELOG.md contains 'SPLIT-01' and 'PASS=186'; ADR-0035 has A1 amendment section (2026-06-02); PR #65 merged to main as commit aa1d60f |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `vendor/agenticapps-shared/migrations/lib/helpers.sh` | Color vars, counters, cleanup, run_check, assert_check, reset_counters | VERIFIED | All six exports present; idempotency guard `_AGENTICAPPS_HELPERS_LOADED`; no set -e |
| `vendor/agenticapps-shared/migrations/lib/fixture-runner.sh` | extract_to ONLY (A1) | VERIFIED | extract_to() defined; no setup_fixture; no workflow template paths; no 1.3.0 |
| `vendor/agenticapps-shared/migrations/lib/preflight.sh` | run_preflight_verify_paths(migrations_dir), set -u safe | VERIFIED | run_preflight_verify_paths() present; reads `${STRICT_PREFLIGHT:-0}`; no REPO_ROOT |
| `vendor/agenticapps-shared/migrations/lib/drift-test.sh` | run_drift_test(skill_md, migrations_dir), no counter mutation | VERIFIED | run_drift_test() present; no `PASS=$((PASS` or `FAIL=$((FAIL` mutations |
| `.gitmodules` | Submodule declaration, canonical HTTPS URL | VERIFIED | `path = vendor/agenticapps-shared`, `url = https://github.com/agenticapps-eu/agenticapps-shared` |
| `migrations/run-tests.sh` | Sources shared lib, setup_fixture WORKFLOW wrapper, WORKFLOW bodies | VERIFIED | Sources all 4 libs; setup_fixture kept as wrapper; WORKFLOW bodies intact; SHARED bodies removed |
| `install.sh` | submodule sync+update when .gitmodules + .git exist | VERIFIED | Guard on `.gitmodules` AND `.git`; runs sync+update; no VERSION-missing guard (A3) |
| `docs/decisions/0035-shared-extraction-boundaries.md` | setup_fixture in WORKFLOW set; A1 amendment recorded | VERIFIED | WORKFLOW set table contains setup_fixture with A1 rationale; amendment section at line 129; SHARED set no longer lists setup_fixture |
| `agenticapps-shared/tests/run-tests.sh` | GREEN standalone suite, PASS=12, A2+A5 coverage | VERIFIED | Exits 0; PASS=12 FAIL=0; covers extract_to real-ref, preflight strict+non-strict, drift GREEN+RED, set -u probe; no setup_fixture; no test_migration_ |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| migrations/run-tests.sh | vendor/agenticapps-shared/migrations/lib/*.sh | BASH_SOURCE[0] dirname → _SHARED_LIB | WIRED | Lines 35-66: _src + _SCRIPT_DIR + _SHARED_LIB resolve; 4 source calls present |
| run-tests.sh:setup_fixture | shared extract_to (WORKFLOW wrapper A1) | setup_fixture() calls extract_to 3x + 1x conditional | WIRED | Lines 113-133: extract_to "$ref" "templates/..." called; 1.3.0 special-case kept |
| run-tests.sh:test_skill_md_version (policy wrapper) | drift-test.sh:run_drift_test (mechanism) | `if run_drift_test "$REPO_ROOT/skill/SKILL.md" "$REPO_ROOT/migrations"` | WIRED | Lines 2134-2141: policy wrapper owns PASS/FAIL; mechanism returns 0/1 only |
| run-tests.sh:test_preflight_verify_paths (policy wrapper) | preflight.sh:run_preflight_verify_paths | `run_preflight_verify_paths "$REPO_ROOT/migrations"` | WIRED | Line 1735: thin wrapper delegates to shared function |
| superproject gitlink | 28-02 release SHA (A4) | git ls-tree HEAD vendor/agenticapps-shared | WIRED | Gitlink SHA: 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4 == 28-02 recorded SHA |
| install.sh | submodule sync+update | .gitmodules + .git guard → sync + update --init --recursive | WIRED | Lines 30-37: both conditions + both git commands present |

---

### Data-Flow Trace (Level 4)

Not applicable — this phase produces bash library infrastructure (sourced shell functions), not components rendering dynamic data. The relevant data flow is the test harness itself, proven by the hard gate: `bash migrations/run-tests.sh` → PASS=186 FAIL=4 with real fixture execution.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Suite baseline PASS=186 FAIL=4 (HARD GATE) | `bash migrations/run-tests.sh` | `PASS: 186 / FAIL: 4` | PASS |
| Drift test still PASSES | grep from suite output | `PASS: test-skill-md-version-matches-latest-migration-to-version` | PASS |
| Shared standalone suite GREEN | `bash agenticapps-shared/tests/run-tests.sh` | `PASS: 12 FAIL: 0 SKIP: 0` | PASS |
| Gitlink SHA matches recorded release SHA | `git ls-tree HEAD vendor/agenticapps-shared` | `1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4` == 28-02 recorded | PASS |
| install.sh non-git guard present | grep install.sh | `.git` dir/file check present; `submodule sync` + `submodule update --init` | PASS |

---

### Requirements Coverage

| Requirement | Plan(s) | Description | Status | Evidence |
|-------------|---------|-------------|--------|----------|
| SC-1 | 28-01 | Four shared lib files carved with SHARED functions | SATISFIED | All four files exist in submodule with correct content |
| SC-2 | 28-03 | claude-workflow vendors agenticapps-shared as submodule; fresh-clone via --recurse-submodules | SATISFIED | .gitmodules present; gitlink SHA 1f5d543; install.sh advances submodule |
| SC-3 | 28-03 | Suite baseline preserved EXACTLY at PASS=186 FAIL=4 | SATISFIED | Ran live — confirmed |
| SC-4 | 28-01/03 | Drift test still PASSES; mechanism shared, policy stays | SATISFIED | run_drift_test mechanism in drift-test.sh; policy wrapper in run-tests.sh; drift PASS confirmed |
| SC-5 | 28-01 | No obs/GSD code in shared lib; setup_fixture NOT carved (A1) | SATISFIED | Grep gate clean; fixture-runner.sh has no setup_fixture |
| SC-6 | 28-03 | GSD command outputs byte-identical before/after | SATISFIED | A6 diff empty (gsd-tools external to repo; byte-identical by construction + captured) |
| SC-7 | 28-02/03 | CHANGELOG records extraction; ADR-0035 amended | SATISFIED | CHANGELOG has SPLIT-01 + PASS=186; ADR-0035 has A1 amendment; agenticapps-shared CHANGELOG has D-28b provenance |
| SC-8 | 28-03 | PR opened to claude-workflow main with concrete body | SATISFIED | PR #65 merged to main (commit aa1d60f); concrete body with release SHA, links, footer |
| D-28a | 28-03 | Sharing mechanism = git submodule | SATISFIED | vendor/agenticapps-shared submodule present |
| D-28b | 28-01/02 | Provenance-by-note (no filter-repo for intermingled functions) | SATISFIED | Lib files have provenance headers citing 5aff1b1; CHANGELOG corrects false filter-repo claim |
| D-28c | 28-01 | SHARED/WORKFLOW boundary = ADR-0035 annotations (canonical) | SATISFIED | ADR-0035 amended; run-tests.sh annotation above setup_fixture reads WORKFLOW |
| D-28d | 28-01/03 | Drift MECHANISM shared, POLICY stays in claude-workflow | SATISFIED | run_drift_test has no counter mutation; policy wrapper in run-tests.sh owns PASS/FAIL |
| D-28e | 28-03 | run-tests.sh source-and-keep (not thin shim) | SATISFIED | All WORKFLOW per-migration bodies kept alongside sourcing block |
| D-28f | 28-03 | Full GSD plan cycle: gsd-plan-checker + cross-AI /gsd-review | SATISFIED | Reviews in 28-REVIEWS.md (codex HIGH + gemini LOW); all A1-A7 addressed |

---

### Anti-Patterns Found

| File | Pattern | Severity | Assessment |
|------|---------|----------|------------|
| migrations/run-tests.sh | Pre-existing `set -e` inside `test_sigterm_mid_apply_preserves_state()` | Info | Pre-existing; always paired with `set +e`; not introduced by this refactor; confirmed via git diff (no `+.*set -e` lines added) |

No blockers or warnings. The `set -e` occurrences are inside a WORKFLOW test body for signal testing and predate SPLIT-01.

---

### Human Verification Required

None. All observable truths are verifiable programmatically. The fresh-clone check (SC-2) was proven in 28-03-SUMMARY.md via the A3 stale-gitlink advance test (install.sh rewound submodule to 556e337 then re-ran install.sh, which advanced back to 1f5d543). The PR #65 is already merged.

---

### Gaps Summary

No gaps. All 9 observable truths verified against the actual codebase on main. The hard gate (PASS=186 FAIL=4) ran live and confirmed. The standalone shared suite (PASS=12) ran live and confirmed. Gitlink SHA 1f5d543 matches the 28-02 recorded release SHA exactly.

---

_Verified: 2026-06-02T18:41:20Z_
_Verifier: Claude (gsd-verifier)_
