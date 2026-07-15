#!/bin/sh
# Verify 0029 heals a CLAUDE.md carrying TWO provenance+block pairs down to
# exactly one of each (I-2). Covers the `swallowed_own_h2` reset at the
# terminator in Step 1's strip pass: without the reset, the first block's
# stale swallow state leaks into the second block, so the second block's own
# heading is mistaken for ITS terminator — leaving that heading and its full
# body un-stripped and orphaned in the result (1 provenance / 2 headings).
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

# Pre-condition: two provenance lines and two headings before healing.
[ "$(grep -c 'spec-source: .* §11' CLAUDE.md)" -eq 2 ] || {
  echo "PRE: fixture must start with two provenance lines"
  exit 1
}
[ "$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)" -eq 2 ] || {
  echo "PRE: fixture must start with two §11 headings"
  exit 1
}

apply_step1

n_prov=$(grep -c 'spec-source: .* §11' CLAUDE.md)
[ "$n_prov" -eq 1 ] || { echo "FAIL: expected exactly 1 provenance line after heal, got $n_prov"; exit 1; }

n_head=$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)
[ "$n_head" -eq 1 ] || { echo "FAIL: expected exactly 1 §11 heading after heal, got $n_head (duplicate heading + orphaned body means the swallowed_own_h2 reset is missing)"; exit 1; }

# Project content from both sides of the original two blocks must survive.
grep -q '^## Workflow$' CLAUDE.md || { echo "FAIL: 'Workflow' project heading lost"; exit 1; }
grep -q 'First project section.' CLAUDE.md || { echo "FAIL: 'Workflow' project content lost"; exit 1; }
grep -q '^## Deployment$' CLAUDE.md || { echo "FAIL: 'Deployment' project heading lost"; exit 1; }
grep -q 'Second project section.' CLAUDE.md || { echo "FAIL: 'Deployment' project content lost"; exit 1; }

echo "OK: 0029 heals a two-provenance CLAUDE.md down to exactly one provenance and one heading"
exit 0
