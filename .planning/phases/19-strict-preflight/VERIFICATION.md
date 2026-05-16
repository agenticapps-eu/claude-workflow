# Phase 19 Verification

## Obligation matrix

| # | Obligation | Evidence | Status |
|---|-----------|----------|--------|
| 1 | Default (loose) mode unchanged | `bash migrations/run-tests.sh \| tail -3` reports `PASS: 131`; exit code `0`. Audit summary line reads `(NOT counted in suite totals — pass --strict-preflight to gate.)`. | ✅ |
| 2 | `--strict-preflight` CLI flag works | `bash migrations/run-tests.sh --strict-preflight \| tail -3` reports `PASS: 131`; exit code `0` on a clean audit. Audit summary line reads `(counted in suite totals — strict mode: 0 audit FAIL to roll in.)`. | ✅ |
| 3 | `STRICT_PREFLIGHT=1` env var works | `STRICT_PREFLIGHT=1 bash migrations/run-tests.sh` behaves identically to the flag form. Exit `0`, same disclaimer. | ✅ |
| 4 | Strict mode catches a broken verify (synthetic regression) | Temporarily replaced `0005`'s verify path with `~/.claude/this-path-does-not-exist/SKILL.md`. Loose mode: exit `0`, audit `FAIL=1`, global `FAIL=0`. Strict mode: exit `1`, audit `FAIL=1`, global `FAIL=1`. Restored cleanly. | ✅ |
| 5 | `--help` flag prints usage | `bash migrations/run-tests.sh --help` emits the comment block from the top of the script (lines 2-N until first blank). Exit `0`. | ✅ |
| 6 | Unknown flags reject with exit 2 | `bash migrations/run-tests.sh --does-not-exist` → stderr `unknown flag: --does-not-exist / run \`migrations/run-tests.sh --help\` for usage`; exit `2`. Distinct from FAIL → exit 1 so CI can tell user error from test failure. | ✅ |
| 7 | Flag is order-agnostic with the filter positional | `bash migrations/run-tests.sh --strict-preflight 0007` runs strict mode + filtered to 0007. `bash migrations/run-tests.sh 0007 --strict-preflight` same. Both verified to produce identical filtered runs. | ✅ |
| 8 | PyYAML-missing path is strict-aware | Code path at `test_preflight_verify_paths()` returns early in both modes if `python3 -c 'import yaml'` fails. Strict mode increments global `FAIL` by 1 with `✗ python3 with PyYAML not available — audit cannot run (strict)`. Loose mode keeps the existing `~` warning. Inspected in `migrations/run-tests.sh:~1340-1355`. | ✅ |
| 9 | Phase 15 smoke unaffected | Smoke runs `bash migrations/run-tests.sh` without flags → loose mode. `bash .planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh 2>&1 \| grep -E '(Passed\|Failed):'` → `Passed: 9 / Failed: 0`. The new disclaimer text is parsed by the smoke's existing PASS/FAIL count awk (no allowlist match required). | ✅ |
| 10 | No scaffolder behaviour change | `git diff main -- 'add-observability/' 'install.sh' 'skill/' 'templates/' 'migrations/0*.md'` shows zero entries. Only `migrations/run-tests.sh`, `migrations/README.md`, `CHANGELOG.md`, and `.planning/` modified. No migration logic, no template, no installer touched. | ✅ |

## Manual reproducer (synthetic regression)

```bash
# Break 0005's verify path
sed -i.bak 's|test -f ~/.claude/skills/gsd-review/SKILL.md|test -f ~/.claude/this-path-does-not-exist/SKILL.md|' \
  migrations/0005-multi-ai-plan-review-enforcement.md

# Loose mode — audit shows FAIL, suite passes
bash migrations/run-tests.sh >/tmp/loose.out 2>&1
echo "loose exit=$?"  # → 0
grep -E "Audit summary|0005:" /tmp/loose.out
# → ✗ 0005: test -f ~/.claude/this-path-does-not-exist/SKILL.md (exit 1)
# → Audit summary: PASS=14 FAIL=1 SKIP=4

# Strict mode — audit FAIL gates suite exit
bash migrations/run-tests.sh --strict-preflight >/tmp/strict.out 2>&1
echo "strict exit=$?"  # → 1
grep -E "Audit summary|0005:|FAIL:" /tmp/strict.out
# → ✗ 0005: test -f ~/.claude/this-path-does-not-exist/SKILL.md (exit 1)
# → Audit summary: PASS=14 FAIL=1 SKIP=4
# → FAIL: 1

# Env-var form, same outcome
STRICT_PREFLIGHT=1 bash migrations/run-tests.sh >/tmp/env.out 2>&1
echo "env exit=$?"  # → 1
grep -E "strict mode" /tmp/env.out
# → (counted in suite totals — strict mode: 1 FAIL rolled into global FAIL.)

# Restore
mv migrations/0005-multi-ai-plan-review-enforcement.md.bak \
   migrations/0005-multi-ai-plan-review-enforcement.md
```

## Counts (no fixture-count change)

| Metric | Before Phase 19 | After Phase 19 |
|--------|----------------:|---------------:|
| Suite PASS (default) | 131 | 131 |
| Suite FAIL (default) | 0 | 0 |
| Audit PASS | 15 | 15 |
| Audit FAIL | 0 | 0 |
| Audit SKIP | 4 | 4 |
| Phase 15 smoke PASS | 9 | 9 |
| Phase 15 smoke FAIL | 0 | 0 |

Phase 19 is feature-add, not regression-fix — no count changes. The new
mode (strict) is opt-in.

## Notes

- The flag uses the existing `RAN_AUDIT=1` sentinel + audit_pass/fail/skip
  locals; no new global state.
- `set -uo pipefail` is on at script level, so `STRICT_PREFLIGHT` is
  pre-initialised via `${STRICT_PREFLIGHT:-0}` to avoid unbound-variable
  errors when neither flag nor env var is set.
- The smoke unchanged because it parses `^[[:space:]]*PASS:` / `^[[:space:]]*FAIL:`
  out of the summary block and doesn't read the audit disclaimer line.
