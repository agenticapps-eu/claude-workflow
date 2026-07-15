#!/bin/sh
# Fixture 03 — BEFORE: §11 correctly anchored above a late region (state A).
# This is the shape of cparx / fx-signal / callbot. 0029 must not touch it.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n## Project Overview\nStuff.\n\n'
  printf '<!-- gitnexus:start -->\n# GitNexus\n\n## Always Do\n- x\n<!-- gitnexus:end -->\n'
} > CLAUDE.md
