#!/bin/sh
# Verify 0029's Step 1 Apply refuses (exit 3) on a file whose second provenance
# region is malformed (no heading), rather than deleting that region and the
# entire file tail. REACHABLE: the stale `@0.3.0` provenance makes the real
# idempotency check report not-applied. Asserted explicitly.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

set +e; check_step1_idempotent; idem=$?; set -e
[ "$idem" -ne 0 ] || {
  echo "FAIL: shape is already-applied (idempotency=0); Apply would be skipped"
  exit 1
}

before="$(cat CLAUDE.md)"

set +e
out="$(apply_step1 2>&1)"
rc=$?
set -e

[ "$rc" -eq 3 ] || {
  echo "FAIL: expected exit 3 (refuse) on malformed second region, got $rc: $out"
  exit 1
}
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refused but still modified CLAUDE.md"
  printf '%s\n' "$before" > CLAUDE.md.before
  diff CLAUDE.md.before CLAUDE.md || true
  exit 1
}
grep -q 'SECRET IN THE MALFORMED SECOND REGION' CLAUDE.md || {
  echo "FAIL: operator content in the second region was deleted"
  exit 1
}
grep -q 'KEEP THE ENTIRE TAIL' CLAUDE.md || {
  echo "FAIL: the file tail after the malformed region was deleted (run-to-EOF)"
  exit 1
}
if ls CLAUDE.md.0029.* >/dev/null 2>&1; then
  echo "FAIL: Step 1 Apply left a stray CLAUDE.md.0029.* temp file behind"
  exit 1
fi

echo "OK: 0029 Apply refuses (exit 3) a malformed second provenance region; tail intact"
exit 0
