#!/bin/sh
# Verify 0029 refuses a hand-pasted §11 block (exit 3) and leaves it untouched.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

before="$(cat CLAUDE.md)"

set +e
out="$(apply_step1 2>&1)"
rc=$?
set -e

[ "$rc" -eq 3 ] || { echo "FAIL: expected exit 3 on unmanaged conflict, got $rc: $out"; exit 1; }
[ "$before" = "$(cat CLAUDE.md)" ] || { echo "FAIL: refused but still modified CLAUDE.md"; exit 1; }
grep -q 'Hand-pasted content' CLAUDE.md || { echo "FAIL: operator content clobbered"; exit 1; }

echo "OK: 0029 refuses a hand-pasted §11 block with exit 3, file untouched"
exit 0
