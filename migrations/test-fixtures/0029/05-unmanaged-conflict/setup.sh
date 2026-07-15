#!/bin/sh
# Fixture 05 — BEFORE: a §11 heading with NO provenance comment. The operator
# hand-pasted it outside the migration's management. 0029 must refuse rather
# than silently overwrite (inherits 0014's conflict rule).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > CLAUDE.md <<'EOF_CLAUDE'
# CLAUDE.md

## Coding Discipline (NON-NEGOTIABLE)

Hand-pasted content the operator wrote themselves. Must not be clobbered.

## Workflow
Stuff.
EOF_CLAUDE
