#!/bin/sh
# Fixture 13 — BEFORE: a §11 block (byte-identical to the canonical mirror)
# correctly anchored, but with operator prose after the block body and before
# the next `## ` heading — the same shape as fixture 12, exercised against
# Step 1 ROLLBACK rather than Apply. Rollback's removal pass strips the entire
# region H..E, so without the guard it deletes this prose along with the block.
# The rollback guard must REFUSE (exit 3) and leave CLAUDE.md byte-identical,
# matching the Apply guard fixture 12 pins.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\nOPERATOR PROSE: how our team applies these four rules in practice.\n'
  printf 'This paragraph is mine, not the spec block, and must survive rollback.\n\n'
  printf '## Project Overview\nStuff.\n'
} > CLAUDE.md
