#!/bin/sh
# Fixture 05 — BEFORE: the stale block, followed by a `## ` heading.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  make_stale_block
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
