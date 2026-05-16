# Phase 18 Verification

## Obligation matrix

| # | Obligation | Evidence | Status |
|---|-----------|----------|--------|
| 1 | `03-no-gitnexus` fixture fails install with exit 1 | `bash migrations/run-tests.sh \| grep '03-no-gitnexus'` → `✓ 03-no-gitnexus (exit 1)`. | ✅ |
| 2 | All 18 `test_migration_0007` fixtures PASS | `bash migrations/run-tests.sh \| sed -n '/Migration 0007/,/Migration 0009/p' \| grep -c '^\s*✓'` → `18`. | ✅ |
| 3 | Full migration suite reaches PASS=131 FAIL=0 | `bash migrations/run-tests.sh \| tail -3` reports `PASS: 131` with no FAIL line (run-tests.sh elides `FAIL: 0`). | ✅ |
| 4 | Zero failing test lines in the run-tests output | `bash migrations/run-tests.sh \| grep -cE '^[[:space:]]*✗'` returns `0`. | ✅ |
| 5 | Host fnm-managed `gitnexus` still on PATH (the failure mode that motivated the fix is still present in the host env) | `command -v gitnexus` returns `/Users/donald/.local/state/fnm_multishells/.../bin/gitnexus`. The fix isolates the test from this leak; it does not modify the host. | ✅ |
| 6 | Hermetic sandbox blocks host gitnexus | Manual reproducer: `tmp=$(mktemp -d); fake_home="$tmp/home"; …setup 03-no-gitnexus…; env -i HOME="$fake_home" PATH="$fake_home/bin:/usr/bin:/bin" bash templates/.claude/scripts/install-gitnexus.sh; echo exit=$?` → `ERROR: gitnexus not installed (or not executable) / Run: npm install -g gitnexus / exit=1`. | ✅ |
| 7 | Pre-fix reproducer (leaky PATH) demonstrates the bug | Same setup with `PATH="$fake_home/bin:$PATH"` → `exit=0` (host gitnexus shadows the removed stub, install script proceeds silently). | ✅ |
| 8 | Required tools (`jq`, `node` via stub, coreutils) all reachable under hermetic PATH | `/usr/bin/jq /usr/bin/sed /usr/bin/awk /usr/bin/grep /bin/cat /bin/mkdir /bin/chmod /bin/mv /bin/rm /bin/ln` all present; `$fake_home/bin/node` is stubbed by `common-setup.sh`. The 18-fixture pass-rate confirms no command-resolution regressions. | ✅ |
| 9 | Phase 15 smoke regression-guard passes with the tightened thresholds | `bash .planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh 2>&1 \| grep -E '(Passed\|Failed):'` → `Passed: 9 / Failed: 0` (one fewer assert than pre-18 because the allowlist-empty branch collapsed into the threshold check). | ✅ |
| 10 | No scaffolder behaviour change | `git diff main -- 'add-observability/' 'install.sh' 'skill/' 'templates/' 'migrations/0*.md'` shows only `migrations/run-tests.sh` (test harness) and `.planning/` (planning artefacts) and `CHANGELOG.md` modified. No template, no skill, no migration logic, no installer touched. | ✅ |

## Before/after counts

| Metric | Before Phase 18 | After Phase 18 |
|--------|----------------:|---------------:|
| Suite PASS | 130 | **131** |
| Suite FAIL | 1 | **0** |
| `test_migration_0007` PASS | 17 | **18** |
| `test_migration_0007` FAIL | 1 | **0** |
| Phase 15 smoke PASS | 10 | 9 |
| Phase 15 smoke FAIL | 0 | 0 |

Note: smoke PASS dropped from 10 to 9 because the "all failures are known
carry-over" assert was redundant once the allowlist became empty; the new
single threshold check (`PASS≥131 FAIL=0`) supersedes both prior asserts.

## Notes

- The fix is generic — any future fixture that adds a sub-script invocation
  through `run_0007_fixture` automatically gets the hermetic sandbox. The
  shape (`env -i HOME=… PATH=…/bin:/usr/bin:/bin bash …`) is also the right
  template to reach for if other migration tests grow shell-execution
  fixtures.
- Future `add-observability` work may add a similar `test_migration_NNNN`
  with shell execution. Carry this pattern forward: hermetic env by
  default, opt-in explicit env vars at the call site, never `PATH=…:$PATH`.
