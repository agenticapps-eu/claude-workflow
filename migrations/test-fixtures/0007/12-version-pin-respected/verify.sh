#!/bin/sh
# command="gitnexus" (not "npx" with --version)
jq -e '.mcpServers.gitnexus.command == "gitnexus"' "$HOME/.claude.json" >/dev/null || exit 1
jq -e '.mcpServers.gitnexus.args == ["mcp"]' "$HOME/.claude.json" >/dev/null || exit 1
