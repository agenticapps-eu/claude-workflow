#!/bin/sh
# Fixture 07 — BEFORE: two provenance lines and two §11 headings. Ambiguous;
# 0030 refuses rather than guess which block is canonical.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$MIRROR"
  printf '\n## Interlude\nStuff.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$MIRROR"
  printf '\n## Project Overview\nMore stuff.\n'
} > CLAUDE.md
