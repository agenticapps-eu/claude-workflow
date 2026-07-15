#!/bin/sh
# Verify pre-flight rule 3 refuses a §11 heading with no provenance line, and
# leaves CLAUDE.md untouched.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

before="$(cat CLAUDE.md)"

if preflight 2>/dev/null; then
  echo "FAIL: pre-flight accepted a §11 heading with no provenance line"
  exit 1
fi

[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refusing pre-flight still mutated CLAUDE.md"
  exit 1
}

echo "OK: pre-flight refused a §11 heading with no provenance line; CLAUDE.md untouched"
exit 0
