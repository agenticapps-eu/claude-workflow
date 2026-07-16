#!/bin/sh
# Verify pre-flight rule 3 refuses two provenance lines + two §11 headings,
# and leaves CLAUDE.md untouched.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

before="$(cat CLAUDE.md)"

out="$(preflight 2>&1)" && {
  echo "FAIL: pre-flight accepted two provenance lines and two §11 headings"
  exit 1
}

# Assert refusal came from rule 3 (exactly-one provenance/heading), not from
# some other failure mode. Without this, deleting rule 3 outright still
# leaves this fixture green — but for the wrong reason: PROV_LINE is
# multi-line ("5\n89"), so rule 4's `$((PROV_LINE + 1))` dies with a shell
# arithmetic syntax error (rc=127). Nothing refused; it crashed. Matching
# only on exit status can't tell the two apart.
printf '%s' "$out" | grep -q 'expected exactly one' || {
  echo "FAIL: pre-flight refused, but not via rule 3 — got:"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}

[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refusing pre-flight still mutated CLAUDE.md"
  exit 1
}

echo "OK: pre-flight refused duplicate provenance/heading pairs; CLAUDE.md untouched"
exit 0
