#!/bin/sh
. "$FIXTURES_ROOT/common-setup.sh"
# Build a subset of default-set repos with .git markers
for rel in agenticapps/claude-workflow factiv/cparx neuroflash/neuroapi; do
  mkdir -p "$HOME/Sourcecode/$rel/.git"
done
