#!/bin/sh
# Fixture 03 — symlink already present + correct target, but version NOT
# yet bumped (e.g. user manually created the symlink, or a prior partial
# apply was interrupted between Step 1 and Step 3). Migration should
# idempotent-skip Steps 1+2 and apply Step 3 (version bump).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Pre-existing symlink, correct target
ln -sfn "$HOME/.claude/skills/agenticapps-workflow/add-observability" \
        "$HOME/.claude/skills/add-observability"
# Version is still 1.10.0 (not yet bumped) — common-setup default
