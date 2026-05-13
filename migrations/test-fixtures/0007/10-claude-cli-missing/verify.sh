#!/bin/sh
jq -e '.mcpServers.gitnexus' "$HOME/.claude.json" >/dev/null || exit 1
