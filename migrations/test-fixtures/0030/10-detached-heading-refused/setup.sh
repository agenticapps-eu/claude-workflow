#!/bin/sh
# Fixture 10 — BEFORE: provenance line, a blank line, THEN the §11 heading —
# the heading is not immediately below the provenance line. Binds pre-flight
# rule 4.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  printf '\n'
  cat "$MIRROR"
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
