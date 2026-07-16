#!/bin/sh
# Fixture 06 — BEFORE: a §11 heading and block present, but no provenance
# comment above it. 0014 never ran here (or it was stripped); injecting a
# managed block is 0029's job, not 0030's, so pre-flight rule 3 refuses.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  cat "$MIRROR"
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
