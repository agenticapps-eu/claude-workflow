#!/bin/sh
"$FIXTURES_ROOT/02-fresh-install/setup.sh"
# Remove the plugins dir if 02-fresh-install setup created it
rm -rf "$HOME/.claude/plugins"
# Confirm .claude exists but not plugins
test -d "$HOME/.claude" && ! test -e "$HOME/.claude/plugins"
