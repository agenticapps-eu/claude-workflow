#!/bin/sh
# Verify 0029 Step 1 skips informationally when there is no CLAUDE.md, creates
# no file, and does not abort.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

[ -f CLAUDE.md ] && { echo "PRE: fixture must have no CLAUDE.md"; exit 1; }

out="$(apply_step1 2>&1)" || { echo "FAIL: Step 1 aborted on absent CLAUDE.md: $out"; exit 1; }

[ -f CLAUDE.md ] && { echo "FAIL: Step 1 created a CLAUDE.md; it must not"; exit 1; }
case "$out" in
  *INFO*) ;;
  *) echo "FAIL: expected an INFO skip message, got: $out"; exit 1 ;;
esac

echo "OK: 0029 skips informationally on an absent CLAUDE.md without creating one"
exit 0
