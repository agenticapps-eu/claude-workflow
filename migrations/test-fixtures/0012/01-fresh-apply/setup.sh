#!/bin/sh
# Fixture 01 — fresh apply (before state).
# v1.10.0 project, scaffolder installed globally, NO symlink yet at
# $HOME/.claude/skills/add-observability.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
# Nothing else — the canonical before state is: no symlink, no version bump.
