#!/bin/sh
# Fixture 12 — BEFORE: a §11 block correctly anchored (byte-identical to the
# canonical mirror), but with operator prose written AFTER the block's closing
# paragraph and BEFORE the next `## ` heading. §11 has no end marker, so the
# managed region is implicitly "provenance -> last non-blank line before the
# next `## ` or `<!-- gitnexus:start -->`". That prose therefore falls inside
# the strip region H..E.
#
# Before the refuse-guard, 0029's Step 1 strip swallowed everything from the
# provenance line to the terminator — deleting this prose — then re-inserted the
# canonical mirror without it, and reported success (the whole-file output stays
# non-empty, so the `[ -s ]` guard never fired). This fixture pins the fix: the
# region's non-blank content differs from the mirror, so 0029 must REFUSE (exit
# 3) and leave CLAUDE.md byte-identical, exactly as migration 0030 does for the
# same shape.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\nOPERATOR PROSE: how our team applies these four rules in practice.\n'
  printf 'This paragraph is mine, not the spec block, and must survive.\n\n'
  printf '## Project Overview\nStuff.\n'
} > CLAUDE.md
