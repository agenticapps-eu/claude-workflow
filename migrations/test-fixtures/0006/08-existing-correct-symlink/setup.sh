#!/bin/sh
"$FIXTURES_ROOT/02-fresh-install/setup.sh"
mkdir -p "$HOME/.claude/plugins"
ln -s "$HOME/Sourcecode/agenticapps/wiki-builder/plugin" "$HOME/.claude/plugins/llm-wiki-compiler"
