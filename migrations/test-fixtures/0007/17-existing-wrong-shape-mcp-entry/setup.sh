#!/bin/sh
. "$FIXTURES_ROOT/common-setup.sh"
# Pre-existing entry with WRONG shape — uses npx instead of gitnexus
echo '{"mcpServers":{"gitnexus":{"command":"npx","args":["-y","gitnexus","mcp"]}}}' > "$HOME/.claude.json"
