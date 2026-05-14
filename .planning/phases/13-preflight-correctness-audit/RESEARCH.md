# Phase 13 — Preflight-correctness audit — RESEARCH

**Date:** 2026-05-14
**Motivation:** Issue #18 (Phase 12 fix) — migration 0005's
`requires.verify` path was wrong on every install. The bug shipped
because no automated check exercised the verify command against a real
environment pre-merge. Phase 13 adds that check.

## Problem

The migration runner's Step 5 (per-migration preflight) runs each
migration's `requires[*].verify` shell command at apply time. If the
command exits non-zero, the migration aborts. Issue #18 showed this
fires correctly — but only at apply time, against a real consumer
project. Authors merging chain-touching PRs have no pre-merge signal
that the verify path resolves.

The `migrations/run-tests.sh` suite tests **idempotency-check** correctness
(does each step's "should this apply?" gate return the right result on
before/after fixtures). It does **not** test verify-path correctness.

## Bug class to prevent

Verify paths that point at locations which:
1. Don't exist on any system (issue #18 — `commands/gsd-review.md` was
   never a real path).
2. Exist on the author's machine but not the documented install layout
   (subtle: passes locally, breaks for users).
3. Existed once and were moved (verify rot).

The Phase 11 → Phase 12 sequence illustrates pattern 3: re-anchoring
0008/0009 frontmatter didn't surface 0005's stale verify because the
chain-walk simulation only exercises `from_version` matching, not
preflight verify.

## Alternatives considered

### Alternative A — Execute verify against host environment (RECOMMENDED)

Add a runner stanza that walks every migration in `migrations/[0-9]*.md`,
parses the `requires` block, and executes each `verify` shell command
against the host. PASS = exit 0; FAIL = anything else; SKIP = no
`requires` block or no `verify` clause.

**Pros:**
- Catches exactly the issue-#18 bug class. Pre-merge, on the author's
  machine, before push.
- Surfaces environment-installation gaps as honest signal ("you don't
  have gsd-review installed locally — did you mean to land a PR that
  depends on it?").
- Trivial to extend as new migrations land.

**Cons:**
- Environment-dependent. CI without all dependencies installed will
  see FAIL counts that don't represent real breakage.
- Mitigation: do NOT count audit failures in the suite's overall
  PASS/FAIL tally. Present as a separate informational section, with a
  clear "this checks YOUR environment, not the chain" disclaimer.

### Alternative B — Static lint of verify strings (REJECTED)

Parse each `verify` string. Validate it starts with `test -f` or
`command -v` (whitelist of allowed verb forms), reject obvious typos,
maybe check that referenced paths plausibly exist (regex match against
known good prefixes like `~/.claude/skills/`).

**Pros:**
- Environment-independent. Works in CI.

**Cons:**
- Would NOT have caught issue #18. The bad path
  `~/.claude/get-shit-done/commands/gsd-review.md` is syntactically
  plausible (`test -f` start, plausible path prefix). Static lint can't
  tell good paths from rot.
- Whitelist is brittle — every new verify shape needs an allowlist
  update.

### Alternative C — Hybrid: lint by default, execute on opt-in flag (REJECTED)

Default to lint (B); add `--exec-verify` to run actual commands (A).

**Pros:**
- CI-friendly default; full check on opt-in.

**Cons:**
- The opt-in flag makes "ran the full check" easy to forget at the
  exact moment it matters (PR open). The check needs to be the default
  for the bug class it catches. Splitting modes reduces signal.

## Decision

**Alternative A.** Implement as `test_preflight_verify_paths()`,
integrated into the main dispatcher (runs alongside per-migration
test stanzas). Audit failures print to a labeled section and report
PASS / FAIL / SKIP counts, but are NOT added to the suite's global
`PASS` / `FAIL` counters — they're informational. The function emits
its own summary line.

This means `bash migrations/run-tests.sh` will still exit 0 even
when the host is missing dependencies. The signal is the labeled
audit summary, which the author reviews before pushing.

If future operators want CI gating, they can grep the audit summary
or post-process the script's output to fail on any `✗` line. Adding
a `--strict-preflight` flag is a separate (optional) follow-up.

## Implementation outline

```bash
test_preflight_verify_paths() {
  local audit_pass=0 audit_fail=0 audit_skip=0

  echo
  echo "${YELLOW}━━━ Preflight-correctness audit (informational) ━━━${RESET}"
  echo "  Exercises each migration's requires.verify against THIS machine."
  echo "  Failures may mean either a broken verify path (real bug) OR a"
  echo "  missing local dependency (expected on fresh machines)."
  echo

  for migration in "$REPO_ROOT/migrations"/[0-9]*.md; do
    local id=$(basename "$migration" | sed 's/-.*//')
    local verifies=$(python3 - "$migration" <<'PY'
import sys, re, yaml
text = open(sys.argv[1]).read()
m = re.search(r'^---\n(.*?)\n---', text, re.DOTALL | re.MULTILINE)
if not m: sys.exit(0)
try:
    fm = yaml.safe_load(m.group(1))
except Exception:
    sys.exit(0)
requires = fm.get('requires') if fm else None
if not requires: sys.exit(0)
for entry in requires:
    if isinstance(entry, dict) and 'verify' in entry:
        print(entry['verify'])
PY
    )

    if [ -z "$verifies" ]; then
      audit_skip=$((audit_skip+1))
      continue
    fi

    while IFS= read -r v; do
      [ -z "$v" ] && continue
      if eval "$v" >/dev/null 2>&1; then
        printf "  ${GREEN}✓${RESET} %s: %s\n" "$id" "$v"
        audit_pass=$((audit_pass+1))
      else
        local rc=$?
        printf "  ${RED}✗${RESET} %s: %s (exit %d)\n" "$id" "$v" "$rc"
        audit_fail=$((audit_fail+1))
      fi
    done <<< "$verifies"
  done

  echo
  printf "  Audit summary: ${GREEN}PASS=%d${RESET} ${RED}FAIL=%d${RESET} ${YELLOW}SKIP=%d${RESET}\n" \
    "$audit_pass" "$audit_fail" "$audit_skip"
  echo "  (NOT counted in suite totals — see disclaimer above.)"
}
```

Add to dispatcher with a `preflight` filter alias:

```bash
if [ -z "$FILTER" ] || [ "$FILTER" = "preflight" ]; then
  test_preflight_verify_paths
fi
```

## Verification plan

1. Run `bash migrations/run-tests.sh` and observe the new audit section
   between the per-migration stanzas and the global summary.
2. On this machine, expected outcome: 0005 verify PASS (Phase 12 fix),
   0006 verify PASS (wiki-compiler vendored), 0007 verifies PASS (jq +
   node ≥ 18 + global gitnexus). 0001/0002/0004/0008/0009/0010 skip (no
   `requires` block).
3. **Synthetic-regression test:** temporarily revert 0005's verify path
   to `~/.claude/get-shit-done/commands/gsd-review.md` (pre-Phase-12
   shape). Confirm the audit reports `✗ 0005` for that verify. Revert
   the revert.
4. Confirm the audit does NOT add to the global PASS/FAIL counters
   (suite still reports the same `PASS: 111 / FAIL: 9` it did pre-Phase-13
   on this machine).

## Out-of-scope

- A `--strict-preflight` flag to gate CI on audit failures — future
  follow-up if/when CI gains parity with author dev environments.
- Tests for migration *body* preflight blocks (the bash that runs in
  `## Pre-flight` sections). Those run against the consumer project's
  filesystem at apply time and aren't structured data we can extract
  generically. Worth a separate phase if it becomes a bug class.
- Lint of verify strings (rejected Alternative B).

## Dependency

Requires `python3` with the `yaml` module (PyYAML). Standard on macOS
where Donald develops; ships pre-installed with Python 3 on most systems.
If the import fails, the audit skips silently with a one-line warning —
no crash, no impact on other tests.
