#!/bin/sh
# Symlink still in place pointing at the right thing
test -L "$HOME/.claude/plugins/llm-wiki-compiler" || exit 1
ACTUAL=$(readlink "$HOME/.claude/plugins/llm-wiki-compiler")
test "$ACTUAL" = "$HOME/Sourcecode/agenticapps/wiki-builder/plugin" || { echo "wrong target: $ACTUAL"; exit 1; }
