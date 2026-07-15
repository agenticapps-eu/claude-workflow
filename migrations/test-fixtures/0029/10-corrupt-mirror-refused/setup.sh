#!/bin/sh
# Fixture 10 — BEFORE: a healthy, correctly-anchored CLAUDE.md (same shape as
# fixture 03's healthy state), on top of common-setup.sh's good vendored
# mirror + 2.6.0 project skeleton. verify.sh corrupts the mirror itself
# (not CLAUDE.md) and asserts both C-1 guard layers refuse (I-A / I-B).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
