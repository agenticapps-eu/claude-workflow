#!/bin/sh
# Migration created plugins parent dir
test -d "$HOME/.claude/plugins" || exit 1
test -L "$HOME/.claude/plugins/llm-wiki-compiler" || exit 1
