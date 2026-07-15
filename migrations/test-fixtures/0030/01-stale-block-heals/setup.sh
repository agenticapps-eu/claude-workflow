#!/bin/sh
# Fixture 01 — BEFORE: the stale block (cparx's real committed bytes) followed
# by a `## ` heading. This is the exact shape of both real targets.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  make_stale_block
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
