#!/bin/sh
"$FIXTURES_ROOT/02-fresh-install/setup.sh"
# Plant a real file where the symlink wants to go
mkdir -p "$HOME/.claude/plugins"
echo "user data" > "$HOME/.claude/plugins/llm-wiki-compiler"
