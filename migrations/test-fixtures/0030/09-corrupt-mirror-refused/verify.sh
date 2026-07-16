#!/bin/sh
# Verify pre-flight rule 1 refuses a truncated vendored §11 mirror (its tail
# sentinel no longer matches the canonical closing line), and leaves
# CLAUDE.md untouched.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

before="$(cat CLAUDE.md)"

if preflight 2>/dev/null; then
  echo "FAIL: pre-flight accepted a truncated vendored §11 mirror"
  exit 1
fi

[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refusing pre-flight still mutated CLAUDE.md"
  exit 1
}

echo "OK: pre-flight refused a truncated vendored §11 mirror; CLAUDE.md untouched"
exit 0
