#!/bin/sh
# Verify pre-flight + Step 1-3 idempotency checks behave as expected on the
# BEFORE state (fixture 01). Migration is not yet applied.
set -eu

# Pre-flight checks should ALL pass on a fresh-apply candidate:
grep -qE '^version: 1\.(10\.0|11\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass (version 1.10.0) but did not"; exit 1; }
test -d "$HOME/.claude/skills/agenticapps-workflow/add-observability" \
  || { echo "PRE-FLIGHT 2 should pass (scaffolder add-observability dir) but did not"; exit 1; }
# Pre-flight #3: nothing at target path → no-op (the [ -e ] && [ ! -L ] check is false)
[ -e "$HOME/.claude/skills/add-observability" ] && { echo "PRE-FLIGHT 3 — fixture should have NO target file"; exit 1; }
true   # explicit pass for PRE-FLIGHT 3 (nothing to check when target absent)
# Pre-flight #4: no existing symlink → no case to evaluate (skip)

# Each step's idempotency check should return NON-ZERO (= "needs to apply"):
# Step 1 — symlink present + correct target
{ test -L "$HOME/.claude/skills/add-observability" \
    && readlink "$HOME/.claude/skills/add-observability" | grep -q '/agenticapps-workflow/add-observability$'; } \
  && { echo "STEP 1 idempotency wrong (symlink should not be present yet)"; exit 1; }
# Step 2 — SKILL.md reachable through symlink + identifies as add-observability
{ test -f "$HOME/.claude/skills/add-observability/SKILL.md" \
    && grep -q '^name: add-observability' "$HOME/.claude/skills/add-observability/SKILL.md"; } \
  && { echo "STEP 2 idempotency wrong (SKILL.md should not be reachable yet)"; exit 1; }
# Step 3 — version bumped to 1.11.0
grep -q '^version: 1.11.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 3 idempotency wrong (version still 1.10.0)"; exit 1; }

echo "fixture 01 — before state correctly reports 'needs to apply' for all 3 steps"
