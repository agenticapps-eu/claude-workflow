#!/bin/sh
# Wrong-shape entry must be PRESERVED (not overwritten)
ACTUAL_CMD=$(jq -r '.mcpServers.gitnexus.command' "$HOME/.claude.json")
test "$ACTUAL_CMD" = "npx" || { echo "entry was overwritten: command=$ACTUAL_CMD"; exit 1; }
# Version bumped anyway (apply continues, just exits 4 with warning)
grep -q '^version: 1.9.3$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || { echo "version not bumped"; exit 1; }
