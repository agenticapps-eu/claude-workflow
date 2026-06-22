#!/bin/sh
# Verify pre-flight + Step 1-2 POSITIVE idempotency anchors on the BEFORE state
# (fixture 01). Migration not yet applied: pre-flight passes, every step's
# positive end-state anchor is ABSENT (so each step "needs to apply").
set -eu

# Pre-flight #1: injection-guard skill present in $HOME -> pass (no abort)
test -f "$HOME/.claude/skills/injection-guard/SKILL.md" \
  || { echo "PRE-FLIGHT 1 should pass (injection-guard skill present) but did not"; exit 1; }
grep -q '^name: injection-guard' "$HOME/.claude/skills/injection-guard/SKILL.md" \
  || { echo "injection-guard SKILL.md should have name: injection-guard"; exit 1; }

# Pre-flight #2: workflow version at supported floor (2.0.0 or 2.1.0 for re-apply)
grep -qE '^version: 2\.(0|1)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 2 should pass (version 2.0.0) but did not"; exit 1; }

# Step 1 idempotency (positive: injection_guard: block present) -> ABSENT before apply
grep -q '^injection_guard:' CLAUDE.md \
  && { echo "STEP 1 idempotency wrong (injection_guard: block should not exist yet)"; exit 1; }
# Step 1 pre-condition: injection-guard skill reachable
test -f "$HOME/.claude/skills/injection-guard/SKILL.md" \
  || { echo "STEP 1 pre-condition: injection-guard skill must be reachable"; exit 1; }

# Step 2 idempotency (positive: ^version: 2.1.0 present) -> ABSENT before apply
grep -q '^version: 2.1.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 2 idempotency wrong (version still 2.0.0 expected)"; exit 1; }
# Step 2 pre-condition: at the 2.0.0 floor
grep -q '^version: 2.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 2 pre-condition: version must be 2.0.0 before apply"; exit 1; }

echo "fixture 01 — pre-flight passes; Steps 1-2 need to apply"
