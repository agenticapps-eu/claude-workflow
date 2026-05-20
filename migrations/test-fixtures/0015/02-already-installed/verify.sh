#!/bin/sh
# Fixture 02 — verify already-installed state: Step 1 idempotency
# returns "applied" (symlink present, target correct); no-op.
set -eu

SCAFFOLDER_SOURCE="$HOME/.claude/skills/agenticapps-workflow/ts-declare-first"
USER_GLOBAL_LINK="$HOME/.claude/skills/ts-declare-first"

# Pre-flight #1: workflow scaffolder at 1.14.0 → pass
grep -q '^version: 1\.14\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass"; exit 1; }

# Pre-flight #2: scaffolder source present → pass
test -f "$SCAFFOLDER_SOURCE/SKILL.md" \
  || { echo "PRE-FLIGHT 2 should pass"; exit 1; }

# Pre-flight #3: a symlink exists at the path (not a regular file/dir)
#   → conflict-detect short-circuits → no abort.
test -L "$USER_GLOBAL_LINK" \
  || { echo "fixture 02 expects symlink at $USER_GLOBAL_LINK"; exit 1; }

# Step 1 idempotency: symlink exists AND points at scaffolder → no-op
test -L "$USER_GLOBAL_LINK" \
  || { echo "STEP 1 expects symlink"; exit 1; }
ACTUAL_TARGET=$(readlink "$USER_GLOBAL_LINK")
[ "$ACTUAL_TARGET" = "$SCAFFOLDER_SOURCE" ] \
  || { echo "STEP 1 idempotency wrong (target=$ACTUAL_TARGET, expected $SCAFFOLDER_SOURCE)"; exit 1; }

echo "fixture 02 — symlink correctly installed; Step 1 returns no-op"
