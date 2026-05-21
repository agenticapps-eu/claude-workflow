#!/bin/sh
# Fixture 04 — unmanaged conflict: user has hand-pasted the canonical
# §11 heading into CLAUDE.md WITHOUT the provenance comment. Pre-flight
# #3 (conflict detect) refuses with exit 3. No migration steps run.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Append the §11 heading directly (simulating an operator who copy-pasted
# the canonical block by hand and didn't include the provenance comment).
# Pre-flight #3 must detect this and refuse.
{
  echo ""
  echo "## Coding Discipline (NON-NEGOTIABLE)"
  echo ""
  echo "Hand-pasted content without provenance management."
} >> CLAUDE.md
