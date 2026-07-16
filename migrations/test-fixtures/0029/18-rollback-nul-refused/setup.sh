#!/bin/sh
# Fixture 18 — BEFORE: a canonical §11 block with a NUL byte inside its heading
# line, exercised against Step 1 ROLLBACK. Rollback shares the clean-text gate
# with Apply, and must refuse any NUL/CR file (exit 3) before its removal awk —
# whose BSD-awk NUL truncation would otherwise let it delete a line whose hidden
# suffix the guard never saw.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  printf '## Coding Discipline (NON-NEGOTIABLE)'; printf '\000'; printf 'SECRET ROLLBACK SUFFIX.\n'
  tail -n +2 "$BLOCK"
  printf '## Tail\nKEEP TAIL.\n'
} > CLAUDE.md
