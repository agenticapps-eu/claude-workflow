# Phase 19 — `--strict-preflight` flag for the preflight audit

## Goal

Add a `--strict-preflight` flag (and equivalent `STRICT_PREFLIGHT=1` env
var) to `migrations/run-tests.sh` that rolls the Phase 13 preflight-
correctness audit's `FAIL` count into the global `FAIL` count. CI
environments with parity to author dev environments can then gate merges
on verify-path rot (the issue-#18 bug class) without affecting dev
workflows that legitimately have host-side dependency gaps.

## Context

Phase 13 (PR #21, commit `65658f7`) introduced `test_preflight_verify_paths`
in `migrations/run-tests.sh`. The audit walks every migration's frontmatter
`requires[*].verify` shell command and executes it against the host. PASS
= exit 0; FAIL = anything else; SKIP = no `requires` block.

Phase 13's RESEARCH.md (line 105) explicitly defers the strict-mode flag:

> If future operators want CI gating, they can grep the audit summary or
> post-process the script's output to fail on any `✗` line. Adding a
> `--strict-preflight` flag is a separate (optional) follow-up.

Phase 19 lands that follow-up.

## Design

### Flag parsing

The existing parser takes the first positional arg as a per-migration
filter (`bash run-tests.sh 0007` → run only the 0007 stanza). The new flag
must coexist with that:

```bash
STRICT_PREFLIGHT="${STRICT_PREFLIGHT:-0}"
FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --strict-preflight) STRICT_PREFLIGHT=1; shift ;;
    -h|--help)          print_usage; exit 0 ;;
    --*)                echo "unknown flag: $1"; exit 2 ;;
    *)                  set FILTER if empty else exit 2 ;;
  esac
done
```

- Order-agnostic: `--strict-preflight 0007` and `0007 --strict-preflight`
  both work.
- Env-var fallback (`STRICT_PREFLIGHT=1`) is more CI-friendly than a CLI
  flag for some runners, and avoids quoting issues in nested shell
  invocations.
- Unknown flags → exit 2 (distinct from FAIL=1 → exit 1).

### Audit behaviour

In strict mode, after the audit's per-verify loop:

```bash
if [ "$STRICT_PREFLIGHT" = "1" ] && [ "$audit_fail" -gt 0 ]; then
  FAIL=$((FAIL + audit_fail))
fi
```

The disclaimer line at the bottom of the audit section changes mode-aware:

- Default: `(NOT counted in suite totals — pass --strict-preflight to gate.)`
- Strict + 0 audit FAIL: `(counted in suite totals — strict mode: 0 audit FAIL to roll in.)`
- Strict + N audit FAIL: `(counted in suite totals — strict mode: N FAIL rolled into global FAIL.)`

The header line also reflects mode: `Preflight-correctness audit (informational)`
vs `… (strict — failures gate exit)`. Mode is visible in the first ~5 lines
of audit output for easy log scanning.

### PyYAML-missing path

The audit early-returns silently when `python3 -c 'import yaml'` fails. In
strict mode this is a real failure: CI without PyYAML can't run the audit,
which masks regressions. New behaviour:

- Loose: same as today (`~ python3 with PyYAML not available — preflight
  audit skipped`).
- Strict: `✗ python3 with PyYAML not available — audit cannot run
  (strict)`, and `FAIL=$((FAIL+1))` before the early return.

## Scope

- `migrations/run-tests.sh` — flag parser (replaces single-positional
  `FILTER` line), audit function gets the strict-mode branches, usage
  comment block expanded.
- `migrations/README.md` — new "Preflight-correctness audit" section
  documenting the audit + both invocation modes + when to use which.
- `CHANGELOG.md` — `### Added` entry under `[1.11.0]`.

## Out of scope

- Wiring `--strict-preflight` into existing smoke tests. Phase 15's smoke
  intentionally uses loose mode so it keeps working on minimal CI images
  that lack the full skill tree.
- A CI workflow file that runs `--strict-preflight`. The flag is the
  primitive; choosing which CI runners get it is project policy, not test-
  harness scope.
- Scaffolder version bump. Test-harness-only feature add; no behaviour
  change for any consumer project; no migration touched.
- Audit changes to read `verify` from sources other than migration
  frontmatter (e.g., per-step preflight bash blocks). The migration
  body's preflight blocks run at apply time against consumer projects
  and aren't easily exercised here; out-of-scope per Phase 13 RESEARCH.md
  line 192-195.

## Verification

- `bash migrations/run-tests.sh` → exit 0, audit summary shows
  `(NOT counted in suite totals — pass --strict-preflight to gate.)`,
  global `PASS: 131`.
- `bash migrations/run-tests.sh --strict-preflight` → exit 0 on a clean
  audit (audit summary shows `(counted in suite totals — strict mode:
  0 audit FAIL to roll in.)`).
- `STRICT_PREFLIGHT=1 bash migrations/run-tests.sh` → same as above.
- `bash migrations/run-tests.sh --help` → prints the usage block from the
  top of the script.
- `bash migrations/run-tests.sh --does-not-exist` → exit 2 with
  `unknown flag: --does-not-exist` on stderr.
- **Synthetic-regression test**: temporarily replace one verify path with
  a non-existent path; run loose mode (exit 0, audit FAIL=1, but global
  FAIL=0); run strict mode (exit 1, global FAIL=1); restore.
- Phase 15 smoke still 9/9 PASS — loose-mode invocation (no flag) means
  the smoke's behavior is unchanged.
