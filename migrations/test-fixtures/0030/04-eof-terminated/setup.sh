#!/bin/sh
# Fixture 04 — BEFORE: stale block at EOF, nothing after it (T = EOF+1 case).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  make_stale_block
} > CLAUDE.md
