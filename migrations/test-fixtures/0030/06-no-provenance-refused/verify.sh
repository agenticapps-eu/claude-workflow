#!/bin/sh
# Verify pre-flight rule 3 refuses a §11 heading with no provenance line, and
# leaves CLAUDE.md untouched.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

before="$(cat CLAUDE.md)"

out="$(preflight 2>&1)" && {
  echo "FAIL: pre-flight accepted a §11 heading with no provenance line"
  exit 1
}

# Assert refusal came from rule 3 (exactly-one provenance/heading), not from
# some other rule firing by accident on the malformed state rule 3 exists to
# catch. Without this, deleting rule 3 outright still leaves this fixture
# green — rule 4 fires instead on an empty PROV_LINE and prints a garbled
# but still non-zero-exit message.
printf '%s' "$out" | grep -q 'expected exactly one' || {
  echo "FAIL: pre-flight refused, but not via rule 3 — got:"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}

[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refusing pre-flight still mutated CLAUDE.md"
  exit 1
}

echo "OK: pre-flight refused a §11 heading with no provenance line; CLAUDE.md untouched"
exit 0
