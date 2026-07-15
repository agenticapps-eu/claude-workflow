#!/bin/sh
# Fixture 11 — BEFORE: a healthy CLAUDE.md whose real §11 block is correctly
# placed (no GitNexus region anywhere in the file), but a guard comment ABOVE
# it MENTIONS the provenance marker in prose — the same shape fixture 07
# exercises for the gitnexus:start/end markers, but for PROV_RE. An
# unanchored PROV_RE substring-matches that prose line and enters `in_block`
# there instead of at the real marker, destroying everything between the
# prose and the block's own heading (including the project rule below) on
# Apply's strip pass.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '<!--\n'
  printf '  The §11 block is anchored behind\n'
  printf '  <!-- spec-source: agenticapps-workflow-core@0.4.0 §11 --> below.\n'
  printf '  This is prose ONLY — the real marker is further down.\n'
  printf '%s\n' '-->'
  printf '\n'
  printf 'IMPORTANT PROJECT RULE: never deploy on Friday.\n'
  printf '\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n## Project Overview\nStuff. No GitNexus region anywhere in this file.\n'
} > CLAUDE.md
