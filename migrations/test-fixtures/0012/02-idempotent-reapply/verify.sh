#!/bin/sh
# Verify all 3 step idempotency checks return 0 (already applied) on the
# AFTER state (fixture 02). Re-running the migration is a no-op.
set -eu

# Pre-flight checks should still all pass on a re-apply candidate:
grep -qE '^version: 1\.(10\.0|11\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass (version 1.11.0 also accepted)"; exit 1; }
test -d "$HOME/.claude/skills/agenticapps-workflow/add-observability" \
  || { echo "PRE-FLIGHT 2 should pass"; exit 1; }
# Pre-flight #3: target IS a symlink → not a real dir, no clobber refuse
if [ -e "$HOME/.claude/skills/add-observability" ] && [ ! -L "$HOME/.claude/skills/add-observability" ]; then
  echo "PRE-FLIGHT 3 should pass — target is a symlink, not real dir"; exit 1
fi
# Pre-flight #4: existing symlink points at right target
EXISTING=$(readlink "$HOME/.claude/skills/add-observability")
case "$EXISTING" in
  */agenticapps-workflow/add-observability) ;;
  *) echo "PRE-FLIGHT 4 — existing symlink should point at scaffolder, got: $EXISTING"; exit 1 ;;
esac

# Each step's idempotency check should return ZERO (= "already applied"):
# Step 1 — symlink present + correct target
test -L "$HOME/.claude/skills/add-observability" \
  && readlink "$HOME/.claude/skills/add-observability" | grep -q '/agenticapps-workflow/add-observability$' \
  || { echo "STEP 1 idempotency wrong (symlink expected to be present + correct target)"; exit 1; }
# Step 2 — SKILL.md reachable + identifies correctly
test -f "$HOME/.claude/skills/add-observability/SKILL.md" \
  && grep -q '^name: add-observability' "$HOME/.claude/skills/add-observability/SKILL.md" \
  || { echo "STEP 2 idempotency wrong (SKILL.md should be reachable + identified)"; exit 1; }
# Step 3 — version bumped to 1.11.0
grep -q '^version: 1.11.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 3 idempotency wrong (version should be 1.11.0)"; exit 1; }

echo "fixture 02 — after state correctly reports 'already applied' for all 3 steps"
