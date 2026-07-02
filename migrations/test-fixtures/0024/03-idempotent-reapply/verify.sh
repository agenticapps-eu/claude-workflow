#!/bin/sh
# Verify migration 0024 idempotency (fixture 03): already applied. Both positive
# anchors hold, so Step 1 (idempotency check) and Step 2 (idempotency check)
# report "already applied" and neither mutates state.
set -eu

# Step 2 positive anchor: version already 2.2.0
grep -q '^version: 2.2.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE: expected version already 2.2.0"; exit 1; }

# Step 1 positive anchor: no whole-tree phases ignore
[ ! -f .gitignore ] || ! grep -qE '^[[:space:]]*/?\.planning/phases/?[[:space:]]*$' .gitignore \
  || { echo "STEP 1 idempotency wrong: whole-tree ignore present in applied state"; exit 1; }

echo "fixture 03 — already at 2.2.0 with phases committed; re-run is a clean no-op"
