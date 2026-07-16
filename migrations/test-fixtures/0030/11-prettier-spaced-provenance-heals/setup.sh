#!/bin/sh
# Fixture 11 — BEFORE: provenance line, ONE blank line, THEN the §11
# heading — prettier's "blank line after an HTML comment" spacing, and the
# real, currently-committed shape of callbot's CLAUDE.md (provenance at
# line 8, heading at line 10; see the migration's root-cause table). Carries
# a STALE block, the same shape fixture 01 heals, just with the
# provenance/heading pair separated by a blank line instead of adjacent.
# Binds pre-flight rule 4's ACCEPT path: this shape is not a defect and
# must not abort — that is the production bug this fixture set exists to
# close.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  printf '\n'
  make_stale_block
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
