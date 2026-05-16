#!/bin/sh
# Fixture 05 — full to_version state. All 3 step idempotency checks pass.
set -eu

# Pre-flight #1: version 1.12.0 → pass (re-apply path)
grep -qE '^version: 1\.(11\.0|12\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass (version 1.12.0 re-apply)"; exit 1; }

# Step 1 idempotency: no vendored → already applied
test ! -e .claude/skills/add-observability \
  || { echo "STEP 1 idempotency wrong"; exit 1; }

# Step 2 idempotency: observability: present → already applied
grep -q '^observability:' CLAUDE.md \
  || { echo "STEP 2 idempotency wrong (observability metadata should be present)"; exit 1; }

# Step 3 idempotency: already at 1.12.0 → already applied
grep -q '^version: 1.12.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 3 idempotency wrong (version should be 1.12.0)"; exit 1; }

echo "fixture 05 — all 3 steps already applied (re-apply is a no-op)"
