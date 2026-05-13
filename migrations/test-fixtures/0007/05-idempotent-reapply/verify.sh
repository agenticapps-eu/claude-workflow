#!/bin/sh
COUNT=$(jq '[.mcpServers.gitnexus] | length' "$HOME/.claude.json")
test "$COUNT" = "1" || { echo "duplicate or missing entry count=$COUNT"; exit 1; }
grep -q '^version: 1.9.3$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || exit 1
