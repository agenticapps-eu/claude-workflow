#!/bin/sh
# Verify migration 0028 is a no-op when .claude/hooks/ is already ignored:
# the idempotency check short-circuits, and applying anyway leaves the file
# byte-identical (no duplicate entry).
set -eu

PI=.prettierignore

# This fixture's .prettierignore already carries the exact entry.
grep -qE '^\.claude/hooks/?$' "$PI" || {
  echo "PRE: fixture must already carry the .claude/hooks entry"; exit 1
}

# ── Step 1 apply — extracted from the migration doc, not copied here ─────────
. "$REPO_ROOT/migrations/test-fixtures/0028/common-verify.sh"

before="$(cat "$PI")"
apply_step1
[ "$before" = "$(cat "$PI")" ] || { echo "not idempotent: apply changed an already-registered .prettierignore"; exit 1; }

n=$(grep -cE '^\.claude/hooks/?$' "$PI")
[ "$n" -eq 1 ] || { echo "duplicate: .claude/hooks/ appears $n times, expected 1"; exit 1; }

echo "OK: 0028 is a no-op when .claude/hooks/ is already ignored (no duplicate)"
exit 0
