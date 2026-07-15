#!/bin/sh
# Fixture 02 — BEFORE: §11 already sits INSIDE the managed region (state B).
# This is what 0014's naive anchor produces on a gitnexus-led file, and what a
# project scaffolded today by setup step e2 still lands in. Not yet eaten;
# 0029 must move it out before the next analyze does.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- gitnexus:start -->\n# GitNexus — Code Intelligence\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n## Always Do\n- MUST run impact analysis.\n<!-- gitnexus:end -->\n\n'
  printf '## Workflow\nProject stuff.\n'
} > CLAUDE.md
