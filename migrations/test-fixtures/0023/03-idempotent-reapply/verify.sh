#!/bin/sh
# Verify both POSITIVE idempotency anchors short-circuit on the AFTER state
# (fixture 03). A second apply must be a no-op: every step's positive end-state
# anchor returns 0 ("already applied — skip").
set -eu

# Step 1: injection_guard: block present in CLAUDE.md
grep -q '^injection_guard:' CLAUDE.md \
  || { echo "STEP 1 idempotency should be satisfied (injection_guard: block present)"; exit 1; }

# Step 2: version 2.1.0 present at the canonical hyphenated path
grep -q '^version: 2.1.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 2 idempotency should be satisfied (^version: 2.1.0)"; exit 1; }
# and the old 2.0.0 line is gone (the bump replaced it)
grep -q '^version: 2.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 2 should have bumped away from 2.0.0"; exit 1; }

echo "fixture 03 — all positive idempotency anchors satisfied; reapply is a no-op"
