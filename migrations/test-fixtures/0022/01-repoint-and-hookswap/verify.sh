#!/bin/sh
# Verify pre-flight + Step 1-4 POSITIVE idempotency anchors on the BEFORE state
# (fixture 01). Migration not yet applied: pre-flight passes, every step's
# positive end-state anchor is ABSENT (so each step "needs to apply").
set -eu

# Pre-flight #1: obs skill present in $HOME -> pass (no abort)
test -f "$HOME/.claude/skills/observability/SKILL.md" \
  || { echo "PRE-FLIGHT 1 should pass (obs skill present) but did not"; exit 1; }
grep -q '^name: observability' "$HOME/.claude/skills/observability/SKILL.md" \
  || { echo "obs SKILL.md should have name: observability"; exit 1; }

# Pre-flight #2: workflow version at supported baseline (1.20.0)
grep -qE '^version: (1\.(20|21)\.0|2\.0\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 2 should pass (version 1.20.0) but did not"; exit 1; }

# Step 1 idempotency (positive: repointed name present) -> ABSENT on before-state
grep -q 'skill: observability' CLAUDE.md \
  && { echo "STEP 1 idempotency wrong (add-observability still expected before apply)"; exit 1; }
grep -q '^observability:' CLAUDE.md \
  || { echo "STEP 1 pre-condition: observability: block must exist"; exit 1; }

# Step 2 idempotency (positive: deterministic hook present) -> ABSENT before apply
test -x .claude/hooks/phase-sentinel.sh \
  && { echo "STEP 2 idempotency wrong (phase-sentinel.sh should not exist yet)"; exit 1; }

# Step 3 idempotency (positive: type:command phase-sentinel hook present) -> ABSENT before apply
jq -e '.. | objects | select(.type? == "command" and (.command? // "" | test("phase-sentinel.sh")))' .claude/settings.json >/dev/null 2>&1 \
  && { echo "STEP 3 idempotency wrong (command hook should not exist yet)"; exit 1; }
# the OLD prompt-type hook IS present on the before-state
jq -e '.. | objects | select(.type? == "prompt" and ((.prompt? // "") | test("current-phase/checklist.md")))' .claude/settings.json >/dev/null 2>&1 \
  || { echo "before-state should still carry the prompt-type Stop hook"; exit 1; }

# Step 4 idempotency (positive: ^version: 2.0.0 present) -> ABSENT before apply
grep -q '^version: 2.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 4 idempotency wrong (version still 1.20.0 expected)"; exit 1; }

echo "fixture 01 — pre-flight passes; Steps 1-4 need to apply"
