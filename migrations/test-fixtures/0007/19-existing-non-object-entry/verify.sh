#!/bin/sh
# Non-object value preserved
ACTUAL_VAL=$(jq -r '.mcpServers.gitnexus' "$HOME/.claude.json")
test "$ACTUAL_VAL" = "some-string-value" || { echo "non-object value overwritten: $ACTUAL_VAL"; exit 1; }
