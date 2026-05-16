#!/bin/sh
# Fixture 03 — Steps 1 + 2 idempotent-pass (symlink present), Step 3 needs apply.
set -eu

# Pre-flight: passes (symlink is right target, version is 1.10.0)
grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass (version 1.10.0)"; exit 1; }
test -L "$HOME/.claude/skills/add-observability" \
  || { echo "fixture 03 expects symlink to exist before verify"; exit 1; }
readlink "$HOME/.claude/skills/add-observability" | grep -q '/agenticapps-workflow/add-observability$' \
  || { echo "PRE-FLIGHT 4 — existing symlink should be correct target"; exit 1; }

# Step 1 idempotent (returns 0): symlink already present, correct target
test -L "$HOME/.claude/skills/add-observability" \
  && readlink "$HOME/.claude/skills/add-observability" | grep -q '/agenticapps-workflow/add-observability$' \
  || { echo "STEP 1 idempotency wrong (expected already-applied)"; exit 1; }
# Step 2 idempotent (returns 0): SKILL.md reachable through symlink
test -f "$HOME/.claude/skills/add-observability/SKILL.md" \
  && grep -q '^name: add-observability' "$HOME/.claude/skills/add-observability/SKILL.md" \
  || { echo "STEP 2 idempotency wrong (expected SKILL.md reachable)"; exit 1; }
# Step 3 NEEDS apply (returns non-zero): version still at 1.10.0
grep -q '^version: 1.11.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 3 idempotency wrong (version should still be 1.10.0)"; exit 1; }

echo "fixture 03 — Steps 1+2 idempotent-pass, Step 3 needs apply"
