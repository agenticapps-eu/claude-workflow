#!/bin/sh
# agenticapps scaffolded
test -f "$HOME/Sourcecode/agenticapps/.wiki-compiler.json" || exit 1
test -d "$HOME/Sourcecode/agenticapps/.knowledge" || exit 1
# experiments NOT scaffolded
test ! -f "$HOME/Sourcecode/experiments/.wiki-compiler.json" || { echo "experiments was scaffolded"; exit 1; }
test ! -d "$HOME/Sourcecode/experiments/.knowledge" || { echo "experiments .knowledge created"; exit 1; }
