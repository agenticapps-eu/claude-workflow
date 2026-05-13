#!/bin/sh
# Entry preserved, version bumped
jq -e '.mcpServers.gitnexus.command == "gitnexus"' "$HOME/.claude.json" >/dev/null || exit 1
grep -q '^version: 1.9.3$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || exit 1
