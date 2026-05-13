#!/bin/sh
test -f "$HOME/.claude.json" || { echo "no .claude.json after install"; exit 1; }
jq -e '.mcpServers.gitnexus' "$HOME/.claude.json" >/dev/null || exit 1
