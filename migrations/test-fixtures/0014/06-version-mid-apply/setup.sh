#!/bin/sh
# Fixture 06 — Step 1 done, Step 2 not yet: simulates the state between
# Step 1's successful apply and Step 2's apply (e.g. a crash mid-migration
# or a partial re-apply). SKILL.md is still at 1.12.0 / 0.3.2 but CLAUDE.md
# already has the §11 section with current provenance @0.4.0.
#
# This proves the two steps are independent: Step 1 is idempotent on its
# own (already applied, no-op), and Step 2 still needs to apply.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Leave SKILL.md at 1.12.0 / 0.3.2 (common-setup default).
# Apply Step 1's effect to CLAUDE.md (anchor + current-version provenance).
{
  echo ""
  echo "<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->"
  cat "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
  echo ""
} >> CLAUDE.md
