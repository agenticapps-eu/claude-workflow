#!/bin/sh
# Verify 0029 is a byte-for-byte no-op on a correctly-anchored file, and stays
# one on re-apply. Step 2 still bumps SKILL.md; only CLAUDE.md is asserted here.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

before="$(cat CLAUDE.md)"

apply_step1
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: 0029 churned a healthy CLAUDE.md. Diff:"
  # Write the comparison file inside the fixture sandbox (the CWD run-tests.sh
  # created and removes), not /tmp — no stray files, no PID-collision games.
  printf '%s\n' "$before" > CLAUDE.md.before
  diff CLAUDE.md.before CLAUDE.md || true
  exit 1
}

apply_step1
[ "$before" = "$(cat CLAUDE.md)" ] || { echo "FAIL: 0029 not idempotent on re-apply"; exit 1; }

echo "OK: 0029 is a byte-identical no-op on a healthy CLAUDE.md, idempotently"
exit 0
