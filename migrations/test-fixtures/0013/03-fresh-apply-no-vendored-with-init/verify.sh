#!/bin/sh
# Fixture 03 — no vendored, init already done. Only Step 3 needs to apply.
set -eu

# Pre-flight #1: version 1.11.0 → pass
grep -qE '^version: 1\.(11\.0|12\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass"; exit 1; }

# Pre-flight #2: no vendored copy → confused-state guard short-circuits
[ -d .claude/skills/add-observability ] && { echo "fixture 03 should have no vendored skill"; exit 1; }

# Step 1 idempotency: no vendored copy → already applied
test ! -e .claude/skills/add-observability \
  || { echo "STEP 1 idempotency wrong"; exit 1; }

# Step 2 idempotency: observability: present → already applied (no init chain)
grep -q '^observability:' CLAUDE.md \
  || { echo "STEP 2 idempotency wrong (observability metadata should be present)"; exit 1; }

# Step 3 idempotency: version 1.11.0 → NEEDS to apply
grep -q '^version: 1.12.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 3 idempotency wrong (version still 1.11.0)"; exit 1; }

echo "fixture 03 — pre-flight passes; Steps 1, 2 already-applied; Step 3 needs to apply"
