#!/bin/sh
# Fixture 14 — BEFORE: a §11 block whose bytes are the canonical mirror, sitting
# INSIDE a GitNexus region (so idempotency reports not-applied and Apply runs —
# a REACHABLE shape, unlike a correctly-anchored current-version block), with
# operator content BETWEEN the provenance line and the block's `## Coding
# Discipline` heading.
#
# The strip enters its managed region at the provenance line and deletes
# everything up to the terminator — including this pre-heading content. A guard
# that only validates from the heading onward (the block region H..E) never sees
# the pre-heading content, passes, and lets the strip delete it. This fixture
# pins the fix: the guard must validate EXACTLY what the strip deletes —
# provenance line onward — so pre-heading content forces a refusal (exit 3).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- gitnexus:start -->\n# GitNexus — Code Intelligence\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  printf 'SECRET PRE-HEADING CONTENT the operator wrote; must survive.\n'
  cat "$BLOCK"
  printf '\n## Always Do\n- MUST run impact analysis.\n<!-- gitnexus:end -->\n\n'
  printf '## Workflow\nProject stuff.\n'
} > CLAUDE.md
