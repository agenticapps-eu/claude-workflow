#!/bin/sh
# Verify 0029 refuses to strip a §11 region that carries operator prose between
# the block body and its terminator, rather than silently deleting it (exit 3,
# CLAUDE.md byte-identical). This is the data-loss path migration 0030 fixed in
# its own replace and explicitly recorded as still live in 0029 (0030 rationale,
# "Prose between the block and its terminator").
#
# Mirrors 0030's guard contract: the region's non-blank content differs from the
# canonical mirror, so the migration must not write through it. The same guard
# also protects a lawful host-added §11 anti-pattern bullet (spec §11 MAY
# clause), which presents identically — non-canonical content inside H..E.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

before="$(cat CLAUDE.md)"

set +e
out="$(apply_step1 2>&1)"
rc=$?
set -e

[ "$rc" -eq 3 ] || {
  echo "FAIL: expected exit 3 (refuse) on prose-in-region, got $rc: $out"
  exit 1
}
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refused but still modified CLAUDE.md"
  printf '%s\n' "$before" > CLAUDE.md.before
  diff CLAUDE.md.before CLAUDE.md || true
  exit 1
}
grep -q 'OPERATOR PROSE' CLAUDE.md || {
  echo "FAIL: operator prose between the block and its terminator was deleted"
  exit 1
}
if ls CLAUDE.md.0029.* >/dev/null 2>&1; then
  echo "FAIL: Step 1 Apply left a stray CLAUDE.md.0029.* temp file behind"
  exit 1
fi

echo "OK: 0029 refuses (exit 3) a §11 region carrying operator prose, file untouched"
exit 0
