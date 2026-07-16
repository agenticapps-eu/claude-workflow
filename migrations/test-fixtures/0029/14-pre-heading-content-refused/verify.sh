#!/bin/sh
# Verify 0029's Step 1 Apply refuses (exit 3) when operator content sits between
# the provenance line and the §11 heading, and leaves CLAUDE.md byte-identical.
# This shape is REACHABLE: the block is inside a GitNexus region, so the real
# idempotency check reports not-applied and the updater would run Apply. Asserted
# explicitly (finding: an isolated-guard fixture that is unreachable via dispatch
# proves nothing about production).
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

# Reachability: idempotency must report NOT-applied (non-zero), else Apply is
# skipped in real operation and this shape can never lose data.
set +e; check_step1_idempotent; idem=$?; set -e
[ "$idem" -ne 0 ] || {
  echo "FAIL: shape is already-applied (idempotency=0); the updater would skip"
  echo "      Apply, so this is not a reachable data-loss shape"
  exit 1
}

before="$(cat CLAUDE.md)"

set +e
out="$(apply_step1 2>&1)"
rc=$?
set -e

[ "$rc" -eq 3 ] || {
  echo "FAIL: expected exit 3 (refuse) on pre-heading content, got $rc: $out"
  exit 1
}
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refused but still modified CLAUDE.md"
  printf '%s\n' "$before" > CLAUDE.md.before
  diff CLAUDE.md.before CLAUDE.md || true
  exit 1
}
grep -q 'SECRET PRE-HEADING CONTENT' CLAUDE.md || {
  echo "FAIL: operator content between the provenance line and the heading was deleted"
  exit 1
}
if ls CLAUDE.md.0029.* >/dev/null 2>&1; then
  echo "FAIL: Step 1 Apply left a stray CLAUDE.md.0029.* temp file behind"
  exit 1
fi

echo "OK: 0029 Apply refuses (exit 3) content between provenance and heading; file untouched"
exit 0
