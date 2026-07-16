#!/bin/sh
# Verify a stray NUL byte does not let the §11 strip bypass its guard. With a
# plain `grep` the guard's presence check misses the provenance (BSD grep treats
# the file as binary), the guard is skipped, and the awk strip deletes the block
# and the trailing SECRET. `grep -a` keeps the guard firing: it must refuse
# (exit 3) with CLAUDE.md byte-identical and the SECRET intact.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

orig="$(mktemp)"; trap 'rm -f "$orig"' EXIT; cp CLAUDE.md "$orig"

set +e
out="$(apply_step1 2>&1)"
rc=$?
set -e

[ "$rc" -eq 3 ] || {
  echo "FAIL: NUL byte bypassed the guard — expected exit 3 (refuse), got $rc: $out"
  exit 1
}
cmp -s "$orig" CLAUDE.md || {
  echo "FAIL: refused but still modified CLAUDE.md (byte comparison)"
  diff "$orig" CLAUDE.md || true
  exit 1
}
grep -aq 'SECRET USER CONTENT' CLAUDE.md || {
  echo "FAIL: operator SECRET content was deleted"
  exit 1
}
grep -aq 'KEEP TAIL' CLAUDE.md || {
  echo "FAIL: the file tail was deleted"
  exit 1
}
if ls CLAUDE.md.0029.* >/dev/null 2>&1; then
  echo "FAIL: Step 1 Apply left a stray CLAUDE.md.0029.* temp file behind"
  exit 1
fi

echo "OK: a stray NUL byte does not bypass the §11 strip guard (grep -a); file untouched"
exit 0
