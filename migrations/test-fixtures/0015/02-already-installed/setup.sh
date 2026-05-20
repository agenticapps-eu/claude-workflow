#!/bin/sh
# Fixture 02 — already installed: symlink at $HOME/.claude/skills/
# ts-declare-first correctly points at the scaffolder source. Step 1
# idempotency check returns "applied"; no-op on re-run.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Install the user-global symlink — simulates the post-apply state.
ln -sfn "$HOME/.claude/skills/agenticapps-workflow/ts-declare-first" \
        "$HOME/.claude/skills/ts-declare-first"
