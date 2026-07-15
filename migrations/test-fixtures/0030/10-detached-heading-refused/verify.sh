#!/bin/sh
# Verify pre-flight rule 4 refuses a §11 heading that is not immediately
# below its provenance line, and leaves CLAUDE.md untouched. Rule 4 enforces
# a precondition the spec's Apply already assumes ("immediately below the
# provenance line"); this fixture is the one that binds it specifically,
# distinct from rules 3's count checks (06/07) and rule 1's mirror-integrity
# check (09).
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

# Pre-condition: exactly one provenance line and one heading (so rule 3 is
# satisfied and rule 4 is the one under test), but NOT adjacent.
[ "$(grep -c '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md)" -eq 1 ] || {
  echo "PRE: fixture must start with exactly one provenance line"
  exit 1
}
[ "$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)" -eq 1 ] || {
  echo "PRE: fixture must start with exactly one §11 heading"
  exit 1
}
prov_line=$(grep -n '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md | cut -d: -f1)
head_line=$(grep -n '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md | cut -d: -f1)
[ "$head_line" -ne $((prov_line + 1)) ] || {
  echo "PRE: fixture must start with the heading detached from the"
  echo "     provenance line (not immediately below it)"
  exit 1
}

before="$(cat CLAUDE.md)"

if preflight 2>/dev/null; then
  echo "FAIL: pre-flight accepted a §11 heading detached from its provenance line"
  exit 1
fi

[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refusing pre-flight still mutated CLAUDE.md"
  exit 1
}

echo "OK: pre-flight rule 4 refused a detached §11 heading; CLAUDE.md untouched"
exit 0
