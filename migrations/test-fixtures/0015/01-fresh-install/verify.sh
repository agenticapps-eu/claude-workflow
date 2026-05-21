#!/bin/sh
# Fixture 01 — verify fresh-install state: pre-flight passes; Step 1
# needs to apply (symlink absent).
set -eu

SCAFFOLDER_SOURCE="$HOME/.claude/skills/agenticapps-workflow/ts-declare-first"
USER_GLOBAL_LINK="$HOME/.claude/skills/ts-declare-first"

# Pre-flight #1: workflow scaffolder at 1.14.0 → pass
grep -q '^version: 1\.14\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass (version 1.14.0)"; exit 1; }

# Pre-flight #2: scaffolder ts-declare-first/SKILL.md exists → pass
test -f "$SCAFFOLDER_SOURCE/SKILL.md" \
  || { echo "PRE-FLIGHT 2 should pass (scaffolder source present)"; exit 1; }

# Pre-flight #3: non-symlink conflict-detect — nothing at the path → pass
test ! -e "$USER_GLOBAL_LINK" \
  || { echo "fixture 01 expects no prior install at $USER_GLOBAL_LINK"; exit 1; }

# Step 1 idempotency: symlink exists AND points at scaffolder → no-op
#   For fixture 01, symlink does NOT exist → NEEDS to apply.
test -L "$USER_GLOBAL_LINK" \
  && { echo "STEP 1 idempotency wrong (no symlink expected on fresh install)"; exit 1; }

echo "fixture 01 — pre-flight passes; Step 1 needs to install user-global symlink"
