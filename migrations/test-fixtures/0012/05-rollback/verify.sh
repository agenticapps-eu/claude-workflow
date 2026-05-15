#!/bin/sh
# Fixture 05 — post-rollback state matches the original v1.10.0 before-state.
set -eu

# Symlink removed
[ -e "$HOME/.claude/skills/add-observability" ] \
  && { echo "ROLLBACK incomplete: symlink still present"; exit 1; }
# Version reverted to 1.10.0
grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "ROLLBACK incomplete: version not reverted to 1.10.0"; exit 1; }
# Scaffolder dir still intact (the rollback doesn't touch the scaffolder)
test -d "$HOME/.claude/skills/agenticapps-workflow/add-observability" \
  || { echo "ROLLBACK should not affect the scaffolder install"; exit 1; }

echo "fixture 05 — rollback restored before-state cleanly"
