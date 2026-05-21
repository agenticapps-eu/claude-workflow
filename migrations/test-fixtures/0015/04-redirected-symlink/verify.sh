#!/bin/sh
# Fixture 04 — verify redirected-symlink state: Step 1 idempotency
# returns "needs apply" (symlink points elsewhere). The migration's
# apply would `ln -sfn` over the redirection.
set -eu

SCAFFOLDER_SOURCE="$HOME/.claude/skills/agenticapps-workflow/ts-declare-first"
USER_GLOBAL_LINK="$HOME/.claude/skills/ts-declare-first"
FORK_PATH="$HOME/.claude/skills/ts-declare-first-fork"

# Pre-flight #1: version 1.14.0 → pass
grep -q '^version: 1\.14\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass"; exit 1; }

# Pre-flight #2: scaffolder source present → pass
test -f "$SCAFFOLDER_SOURCE/SKILL.md" \
  || { echo "PRE-FLIGHT 2 should pass"; exit 1; }

# Pre-flight #3: path exists AND IS a symlink → conflict-detect short-
# circuits (the refusal is specifically for non-symlinks; redirected
# symlinks are handled by Step 1's force-overwrite).
test -L "$USER_GLOBAL_LINK" \
  || { echo "fixture 04 expects symlink at $USER_GLOBAL_LINK"; exit 1; }

# Step 1 idempotency: symlink exists BUT points at fork (not scaffolder)
#   → NEEDS to apply. The apply force-overwrites via `ln -sfn`.
ACTUAL_TARGET=$(readlink "$USER_GLOBAL_LINK")
[ "$ACTUAL_TARGET" = "$SCAFFOLDER_SOURCE" ] \
  && { echo "STEP 1 idempotency wrong (target should be fork, not scaffolder)"; exit 1; }
[ "$ACTUAL_TARGET" = "$FORK_PATH" ] \
  || { echo "fixture 04 expects redirect to fork; got $ACTUAL_TARGET"; exit 1; }

# State: fork's SKILL.md is still there (Step 1 hasn't run).
test -f "$FORK_PATH/SKILL.md" \
  || { echo "fork should still exist on BEFORE state"; exit 1; }

echo "fixture 04 — redirected symlink detected; Step 1 needs apply (force-overwrite)"
