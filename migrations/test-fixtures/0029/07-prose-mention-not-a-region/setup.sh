#!/bin/sh
# Fixture 07 — BEFORE: this repo's own CLAUDE.md shape (C1). A guard comment
# near the top MENTIONS `<!-- gitnexus:start -->` in backticks as prose, the
# §11 block is correctly anchored right after that comment, and there is NO
# real GitNexus-managed region anywhere in the file. An unanchored marker
# regex treats line 2 as "inside a region"; an anchored one does not.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '<!--\n'
  printf '  This block MUST stay ABOVE the `<!-- gitnexus:start -->` region below.\n'
  printf '  This is prose ONLY — this fixture file has no real region.\n'
  printf '%s\n' '-->'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n## Project Overview\nStuff. No GitNexus region anywhere in this file.\n'
} > CLAUDE.md
