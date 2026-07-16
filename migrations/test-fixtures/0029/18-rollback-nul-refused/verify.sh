#!/bin/sh
# Verify Step 1 ROLLBACK's clean-text gate refuses a NUL file (exit 3), leaving
# it byte-identical with the hidden suffix intact — rather than letting BSD awk's
# NUL truncation delete the heading line and its suffix.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

orig="$(mktemp)"; trap 'rm -f "$orig"' EXIT; cp CLAUDE.md "$orig"

set +e
out="$(rollback_step1 2>&1)"
rc=$?
set -e

[ "$rc" -eq 3 ] || {
  echo "FAIL: rollback did not refuse a NUL file — expected exit 3, got $rc: $out"
  exit 1
}
printf '%s\n' "$out" | grep -q 'NUL or CR' || {
  echo "FAIL: rollback refusal did not come from the clean-text gate (no 'NUL or CR'):"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}
cmp -s "$orig" CLAUDE.md || {
  echo "FAIL: rollback refused but still modified CLAUDE.md (byte comparison)"
  exit 1
}
grep -aq 'SECRET ROLLBACK SUFFIX' CLAUDE.md || {
  echo "FAIL: hidden suffix after the NUL was deleted"
  exit 1
}
if ls CLAUDE.md.0029.* >/dev/null 2>&1; then
  echo "FAIL: Step 1 Rollback left a stray CLAUDE.md.0029.* temp file behind"
  exit 1
fi

echo "OK: Step 1 Rollback's clean-text gate refuses a NUL file (exit 3); file untouched"
exit 0
