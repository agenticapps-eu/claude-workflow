#!/bin/sh
. "$FIXTURES_ROOT/common-setup.sh"
# Pre-existing entry is a STRING, not an object
echo '{"mcpServers":{"gitnexus":"some-string-value"}}' > "$HOME/.claude.json"
