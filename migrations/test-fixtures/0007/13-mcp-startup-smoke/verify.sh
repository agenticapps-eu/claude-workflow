#!/bin/sh
# Extract command + args, then invoke
CMD=$(jq -r '.mcpServers.gitnexus.command' "$HOME/.claude.json")
ARG=$(jq -r '.mcpServers.gitnexus.args[0]' "$HOME/.claude.json")
test "$CMD" = "gitnexus" || { echo "CMD=$CMD"; exit 1; }
test "$ARG" = "mcp" || { echo "ARG=$ARG"; exit 1; }
# Invoke the MCP command (gitnexus mcp) — stub exits 0 and records
rm -f "$HOME/.gn-record"
PATH="$HOME/bin:$PATH" "$CMD" "$ARG" || { echo "mcp invocation failed"; exit 1; }
grep -q "^gitnexus mcp$" "$HOME/.gn-record" || { echo "mcp not recorded"; cat "$HOME/.gn-record"; exit 1; }
