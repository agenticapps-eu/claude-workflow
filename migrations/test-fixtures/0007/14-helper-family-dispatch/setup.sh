#!/bin/sh
. "$FIXTURES_ROOT/common-setup.sh"
# Build a fake family with 2 git repos
mkdir -p "$HOME/Sourcecode/factiv/cparx/.git" "$HOME/Sourcecode/factiv/fx-signal-agent/.git"
