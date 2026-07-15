#!/bin/sh
# Fixture 02 — BEFORE: the canonical mirror already in place, verbatim.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$MIRROR"
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
