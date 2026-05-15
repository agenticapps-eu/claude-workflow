#!/bin/sh
# Fixture 06 — requires.tool.claude.verify fails because claude is not in PATH.
# Other state is canonical before-state, but pre-flight aborts.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Remove the stub claude so command -v fails. We also strip $HOME/bin from
# PATH locally; the migration's verify would run `command -v claude` in the
# project context.
rm -f "$HOME/bin/claude"
