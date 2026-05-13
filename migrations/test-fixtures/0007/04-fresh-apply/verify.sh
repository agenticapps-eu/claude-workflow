#!/bin/sh
test -f "$HOME/.claude.json" || { echo "no .claude.json"; exit 1; }
jq -e '.mcpServers.gitnexus.command == "gitnexus"' "$HOME/.claude.json" >/dev/null || { echo "MCP command not gitnexus"; exit 1; }
jq -e '.mcpServers.gitnexus.args[0] == "mcp"' "$HOME/.claude.json" >/dev/null || { echo "MCP args[0] not mcp"; exit 1; }
grep -q '^version: 1.9.3$' "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" || { echo "version not bumped"; exit 1; }
