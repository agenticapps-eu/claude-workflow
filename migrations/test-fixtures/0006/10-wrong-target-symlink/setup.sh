#!/bin/sh
"$FIXTURES_ROOT/02-fresh-install/setup.sh"
mkdir -p "$HOME/.claude/plugins" "$HOME/other-fork"
ln -s "$HOME/other-fork" "$HOME/.claude/plugins/llm-wiki-compiler"
