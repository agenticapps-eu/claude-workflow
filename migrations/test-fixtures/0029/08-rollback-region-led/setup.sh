#!/bin/sh
# Fixture 08 — BEFORE: a HEALED region-led CLAUDE.md — the §11 block already
# sits above a real GitNexus-managed region (the shape 0029's own Apply
# produces on a gitnexus-led file, e.g. fixture 01's AFTER state). This is
# the target Rollback must be able to undo without damaging the region.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nThis file provides guidance to Claude Code.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n'
  printf '<!-- gitnexus:start -->\n# GitNexus — Code Intelligence\n\n'
  printf 'This project is indexed by GitNexus as **demo** (100 symbols).\n\n'
  printf '## Always Do\n- MUST run impact analysis before editing any symbol.\n\n'
  printf '## Never Do\n- NEVER rename symbols with find-and-replace.\n<!-- gitnexus:end -->\n\n'
  printf '## Workflow\nProject-specific stuff here.\n'
} > CLAUDE.md
