#!/bin/sh
# Fixture 04 — symlink at $HOME/.claude/skills/add-observability exists
# but points elsewhere (e.g. user manually pointed it at a fork, or a
# prior install of a different observability skill is registered there).
# Pre-flight #4 must HARD ABORT with exit 3. NO version bump.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Create a wrong-target symlink. Target doesn't even need to exist —
# pre-flight check is purely on the symlink's readlink string.
ln -sfn /tmp/some-other-add-observability "$HOME/.claude/skills/add-observability"
