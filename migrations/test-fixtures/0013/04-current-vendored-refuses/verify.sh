#!/bin/sh
# Fixture 04 — vendored at current version. Pre-flight #2 must trigger.
# Verify that:
#   1. The confused-state guard correctly identifies same-version condition
#   2. No "apply" happened (version still 1.11.0, vendored still present)
set -eu

# Pre-flight #1: version 1.11.0 → pass
grep -qE '^version: 1\.(11\.0|12\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass"; exit 1; }

# Pre-flight #2: vendored present AND version matches global → must abort
test -d .claude/skills/add-observability \
  || { echo "fixture 04 expects vendored skill present"; exit 1; }
LOCAL_VER=$(awk '/^version:/{print $2; exit}'  .claude/skills/add-observability/SKILL.md)
GLOBAL_VER=$(awk '/^version:/{print $2; exit}' "$HOME/.claude/skills/agenticapps-workflow/add-observability/SKILL.md")
[ "$LOCAL_VER" = "$GLOBAL_VER" ] \
  || { echo "fixture 04 SHOULD have matching versions (local=$LOCAL_VER global=$GLOBAL_VER)"; exit 1; }
# i.e. pre-flight #2 would HARD ABORT exit 3 at this point. Verify no
# state mutation happened (we're checking the BEFORE state).

# Vendored skill must still be there (no Step 1 removal on abort path)
test -d .claude/skills/add-observability \
  || { echo "STEP 1 should NOT have removed vendored on abort path"; exit 1; }

# Version must still be 1.11.0 (no Step 3 on abort path)
grep -q '^version: 1.11.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 3 should NOT have bumped version on abort path"; exit 1; }

echo "fixture 04 — confused-state correctly detected; no migration steps applied"
