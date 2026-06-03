#!/bin/sh
# Verify all four POSITIVE idempotency anchors short-circuit on the AFTER state
# (fixture 03). A second apply must be a no-op: every step's positive end-state
# anchor returns 0 ("already applied — skip").
set -eu

# Step 1: repointed name present
grep -q 'skill: observability' CLAUDE.md \
  || { echo "STEP 1 idempotency should be satisfied (skill: observability present)"; exit 1; }
# and the old name is gone (the repoint replaced it)
grep -q 'skill: add-observability' CLAUDE.md \
  && { echo "STEP 1 should have repointed away from add-observability"; exit 1; }

# Step 2: deterministic hook present + executable
test -x .claude/hooks/phase-sentinel.sh \
  || { echo "STEP 2 idempotency should be satisfied (hook present+executable)"; exit 1; }
grep -q 'set -euo pipefail' .claude/hooks/phase-sentinel.sh \
  || { echo "STEP 2: hook body should contain set -euo pipefail"; exit 1; }

# Step 3: type:command phase-sentinel hook PRESENT (positive jq select)
jq -e '.. | objects | select(.type? == "command" and (.command? // "" | test("phase-sentinel.sh")))' .claude/settings.json >/dev/null \
  || { echo "STEP 3 idempotency should be satisfied (command hook present)"; exit 1; }
# and the old prompt-type hook is gone
jq -e '.. | objects | select(.type? == "prompt" and ((.prompt? // "") | test("current-phase/checklist.md")))' .claude/settings.json >/dev/null 2>&1 \
  && { echo "STEP 3 should have removed the prompt-type Stop hook"; exit 1; }
# settings.json still valid JSON
jq . .claude/settings.json >/dev/null \
  || { echo "STEP 3: settings.json must remain valid JSON"; exit 1; }

# Step 4: version 2.0.0 present at the canonical hyphenated path
grep -q '^version: 2.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 4 idempotency should be satisfied (^version: 2.0.0)"; exit 1; }

echo "fixture 03 — all positive idempotency anchors satisfied; reapply is a no-op"
