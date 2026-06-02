---
phase: 28-split-01-agenticapps-shared
plan: "02"
subsystem: agenticapps-shared/tests + agenticapps-shared/CHANGELOG
tags: [bash, testing, standalone-suite, provenance, release, submodule, extract_to, preflight, drift-test]

requires:
  - phase: 28-split-01-agenticapps-shared/28-01
    provides: "four carved lib files (helpers.sh, fixture-runner.sh, preflight.sh, drift-test.sh) in agenticapps-shared/migrations/lib/"

provides:
  - "agenticapps-shared/tests/run-tests.sh — standalone suite proving all fragile shared surfaces (A2+A5)"
  - "agenticapps-shared/migrations/test-fixtures/_example/ — copy-me fixture skeleton"
  - "agenticapps-shared CHANGELOG [1.0.0] with accurate D-28b provenance (no false filter-repo claim)"
  - "agenticapps-shared README updated (removed skeleton status, added test-suite howto)"
  - "Tag v1.0.0 on agenticapps-shared main (provenance tag; pin by commit SHA)"
  - "CANONICAL PIN ARTIFACT: release commit SHA 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4 (28-03 must verify gitlink equals this)"

affects:
  - "28-03 (must pin submodule gitlink to 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4)"

tech-stack:
  added: []
  patterns:
    - "Standalone bash test suite sourcing shared lib via BASH_SOURCE[0] dirname (no claude-workflow context)"
    - "Strict-mode probe counter isolation via save/reset_counters/restore pattern"
    - "Throwaway git repo in mktemp for extract_to real-ref test (avoids touching the live repo)"
    - "set -u subshell probe: source + call in subshell with STRICT_PREFLIGHT unset"

key-files:
  created:
    - "~/Sourcecode/agenticapps/agenticapps-shared/tests/run-tests.sh"
    - "~/Sourcecode/agenticapps/agenticapps-shared/migrations/test-fixtures/_example/setup.sh"
    - "~/Sourcecode/agenticapps/agenticapps-shared/migrations/test-fixtures/_example/verify.sh"
    - "~/Sourcecode/agenticapps/agenticapps-shared/migrations/test-fixtures/_example/expected-exit"
  modified:
    - "~/Sourcecode/agenticapps/agenticapps-shared/CHANGELOG.md"
    - "~/Sourcecode/agenticapps/agenticapps-shared/README.md"

key-decisions:
  - "A2 gate honored: tag v1.0.0 cut ONLY after standalone suite passed GREEN (PASS=12 FAIL=0)"
  - "A4 pin artifact: canonical pin is commit SHA 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4 (tagged v1.0.0); SHA embedded in tag annotation + SUMMARY (not in CHANGELOG content — avoids SHA-amend chicken-and-egg)"
  - "SHA-in-CHANGELOG chicken-and-egg resolved: SHA is in the v1.0.0 tag annotation and this SUMMARY; CHANGELOG references the tag for resolution (no stale hex SHA in CHANGELOG text)"
  - "Push skipped per explicit prompt constraint 'Do NOT push either repo'; tag and commits are local-only pending user push"
  - "Strict-mode test probe counter isolation: save/reset_counters/restore avoids audit FAILs polluting suite totals"

patterns-established:
  - "Standalone lib test: BASH_SOURCE[0] dirname sourcing; trap installed after all sources"
  - "Preflight strict probe: save FAIL before call, measure delta, restore with only assertion-level FAIL"

requirements-completed: [SC-1, SC-7, D-28b]

duration: 26min
completed: 2026-06-02
---

# Phase 28 Plan 02: Standalone Test Suite + 1.0.0 Release — Summary

**Broad standalone suite (PASS=12 FAIL=0) proves extract_to real git-ref, preflight strict+non-strict, drift GREEN+RED, set -u safety; _example fixture skeleton created; agenticapps-shared tagged v1.0.0 at canonical pin SHA `1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4`**

---

## CANONICAL PIN ARTIFACT (A4) — 28-03 reads this

**Release commit SHA: `1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4`**

This is the exact commit tagged `v1.0.0` in `agenticapps-shared`. Plan 28-03's submodule
gitlink MUST equal this SHA. Verify with:

```bash
git -C vendor/agenticapps-shared rev-parse HEAD
# expected: 1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4
```

The `v1.0.0` tag is provenance only (human-readable pointer). The gitlink SHA is the
canonical pin artifact per A4.

---

## Performance

- **Duration:** ~26 min
- **Started:** 2026-06-02T17:33:34Z
- **Completed:** 2026-06-02T17:59:00Z
- **Tasks:** 2
- **Files created:** 4 (run-tests.sh, setup.sh, verify.sh, expected-exit)
- **Files modified:** 2 (CHANGELOG.md, README.md)

## Accomplishments

- Standalone test suite `tests/run-tests.sh` exits 0 with PASS=12 FAIL=0 SKIP=0
- All A2 surfaces proven: `extract_to` real git-ref (throwaway repo), `run_preflight_verify_paths` strict + non-strict, `run_drift_test` GREEN + RED, `assert_check` counter increment
- A5 set -u safety probe: STRICT_PREFLIGHT never set → no unbound-variable crash confirmed
- A1 boundary honored: no `setup_fixture` or `test_migration_*` references in suite
- `_example` fixture skeleton (setup.sh/verify.sh/expected-exit) wired into Test 1
- CHANGELOG [1.0.0] corrected: false filter-repo claim removed, D-28b provenance by note, source SHA `5aff1b1` cited, A1 boundary noted
- README updated: skeleton status removed, "Running the shared test suite" section added
- VERSION confirmed `1.0.0` (no change needed)
- Tag `v1.0.0` created locally as annotated tag; SHA embedded in tag annotation

## Tasks and Commits (agenticapps-shared repo)

| Task | Name | Commit | Key files |
|------|------|--------|-----------|
| 1 | _example fixture + standalone test suite | `556e337` | tests/run-tests.sh, _example/{setup,verify,expected-exit} |
| 2 | CHANGELOG + README + tag v1.0.0 | `1f5d543` | CHANGELOG.md, README.md (tagged v1.0.0) |

## Standalone Suite Coverage (A2 + A5)

| Test | What it proves | Result |
|------|---------------|--------|
| 1 | assert_check via _example fixture | PASS |
| 2 | assert_check PASS counter increment | PASS |
| 3 | run_drift_test GREEN (matching versions) | PASS |
| 4 | run_drift_test RED (mismatched versions) | PASS |
| 5 (A2) | extract_to real git-ref in throwaway repo | PASS |
| 5b (A2) | extract_to nonexistent path returns non-zero | PASS |
| 6 (A2) | run_preflight_verify_paths non-strict: FAIL does not grow | PASS |
| 6b (A2) | run_preflight_verify_paths non-strict: RAN_AUDIT=1 | PASS |
| 7 (A2) | run_preflight_verify_paths strict: FAIL grows | PASS |
| 8 (A5) | set -u safety: STRICT_PREFLIGHT unset → no crash | PASS |
| extra | _example/expected-exit contains 0 | PASS |
| extra | _example fixture: marker created by setup.sh | PASS |

**Suite exit: 0 (GREEN)**

## Deviations from Plan

### 1. [Rule 2 — Design] SHA-in-CHANGELOG chicken-and-egg — resolved by moving SHA to tag annotation + SUMMARY

**Found during:** Task 2 (amend approach for CHANGELOG SHA)

**Issue:** The plan's "amend approach" for embedding the release commit SHA in the CHANGELOG creates an irresolvable chicken-and-egg: every `git commit --amend` that updates the CHANGELOG with the new HEAD SHA produces a new SHA (because the commit content changes). Multiple amend cycles were attempted (initial → `8084e43`, amend1 → `be274f4`, amend2 → `c222ce6`, amend3 → `17969c1`) and each amend produced a new SHA.

**Fix:** Removed the literal hex SHA from CHANGELOG text. Instead:
- The SHA is embedded in the `v1.0.0` tag annotation (immutable after tagging)
- The SHA is recorded prominently in this SUMMARY as the canonical pin artifact
- The CHANGELOG "Release commit" section now references the tag for resolution (`git rev-parse v1.0.0^{}`) rather than embedding a stale hex string

**Impact:** The plan's acceptance criterion `grep -q "$HEAD_SHA" CHANGELOG.md` cannot be satisfied (any commit that changes file content changes its own SHA). The CHANGELOG does contain the provenance narrative, the D-28b language, and the tag reference — fulfilling the intent of A4. The authoritative SHA for 28-03 is `1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4` as recorded here.

**Files modified:** CHANGELOG.md

### 2. [User constraint] Push skipped — explicit prompt prohibition

**Found during:** Task 2 (push step)

**Issue:** The plan specifies `git push origin main` and `git push origin v1.0.0`, but the execution prompt explicitly states "Do NOT push either repo."

**Fix:** Commits and tag exist locally. Push is pending user action.

**Push commands when ready:**
```bash
git -C ~/Sourcecode/agenticapps/agenticapps-shared push origin main
git -C ~/Sourcecode/agenticapps/agenticapps-shared push origin v1.0.0
```

## Verification Results

```
bash tests/run-tests.sh → PASS: 12  FAIL: 0  SKIP: 0  EXIT: 0  ✓
git describe --tags --exact-match HEAD → v1.0.0  ✓
git status --porcelain → (empty — clean tree)  ✓
grep 'Migration provenance' CHANGELOG.md → FOUND  ✓
grep '5aff1b1' CHANGELOG.md → FOUND  ✓
grep 'git log --follow' CHANGELOG.md → in "NOT preserved" negation context  ✓ (criterion met)
cat VERSION → 1.0.0  ✓
git ls-files migrations/lib/ | grep -c '.sh$' → 4  ✓
grep -q 'setup_fixture' tests/run-tests.sh → NOT FOUND (A1)  ✓
grep -q 'test_migration_' tests/run-tests.sh → NOT FOUND (Pitfall 4)  ✓
```

## Known Stubs

None. All files are complete implementations.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes. The
standalone suite creates throwaway git repos in `mktemp` dirs and cleans them via
EXIT trap — no persistent side effects.

## Self-Check: PASSED

| Item | Result |
|------|--------|
| tests/run-tests.sh exists | FOUND |
| _example/setup.sh exists | FOUND |
| _example/verify.sh exists | FOUND |
| _example/expected-exit exists | FOUND |
| CHANGELOG.md exists | FOUND |
| README.md exists | FOUND |
| 28-02-SUMMARY.md exists | FOUND |
| agenticapps-shared commit 556e337 | FOUND |
| agenticapps-shared commit 1f5d543 | FOUND |
| tag v1.0.0 | FOUND |
| standalone suite exit 0 | GREEN |
| release SHA 1f5d543bc6ca... in SUMMARY | FOUND |
