#!/bin/sh
# Verify Step 1 ROLLBACK refuses to remove a §11 region carrying operator prose
# between the block body and its terminator (exit 3, CLAUDE.md byte-identical),
# rather than deleting it. Rollback shares the strip awk — and therefore the
# data-loss — with Apply; this pins the guard on the rollback path too.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

before="$(cat CLAUDE.md)"

set +e
out="$(rollback_step1 2>&1)"
rc=$?
set -e

[ "$rc" -eq 3 ] || {
  echo "FAIL: expected exit 3 (refuse) on rollback of prose-in-region, got $rc: $out"
  exit 1
}
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: rollback refused but still modified CLAUDE.md"
  printf '%s\n' "$before" > CLAUDE.md.before
  diff CLAUDE.md.before CLAUDE.md || true
  exit 1
}
grep -q 'OPERATOR PROSE' CLAUDE.md || {
  echo "FAIL: rollback deleted operator prose between the block and its terminator"
  exit 1
}
if ls CLAUDE.md.0029.* >/dev/null 2>&1; then
  echo "FAIL: Step 1 Rollback left a stray CLAUDE.md.0029.* temp file behind"
  exit 1
fi

echo "OK: 0029 Step 1 Rollback refuses (exit 3) a §11 region carrying operator prose, file untouched"
exit 0
