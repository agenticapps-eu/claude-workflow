#!/bin/sh
# Verify the EOF fallback: no `## ` and no region means append, not drop.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

apply_step1

grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md || {
  echo "FAIL: §11 dropped on a file with no anchor"
  exit 1
}
grep -q 'Just prose' CLAUDE.md || { echo "FAIL: original content lost"; exit 1; }

# NOTE: single quotes — backticks inside a double-quoted string would be
# command substitution and try to execute `## `.
echo 'OK: 0029 appends §11 at EOF when there is no "## " heading and no region'
exit 0
