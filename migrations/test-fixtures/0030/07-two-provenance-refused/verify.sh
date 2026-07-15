#!/bin/sh
# Verify pre-flight rule 3 refuses two provenance lines + two §11 headings,
# and leaves CLAUDE.md untouched.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

before="$(cat CLAUDE.md)"

if preflight 2>/dev/null; then
  echo "FAIL: pre-flight accepted two provenance lines and two §11 headings"
  exit 1
fi

[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refusing pre-flight still mutated CLAUDE.md"
  exit 1
}

echo "OK: pre-flight refused duplicate provenance/heading pairs; CLAUDE.md untouched"
exit 0
