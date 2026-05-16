#!/bin/sh
# Verify pre-flight + Step 1-3 idempotency checks behave as expected on the
# BEFORE state (fixture 01). Migration is not yet applied.
set -eu

# Pre-flight #1: version is 1.11.0 → pass
grep -qE '^version: 1\.(11\.0|12\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass (version 1.11.0) but did not"; exit 1; }

# Pre-flight #2: no project-local vendored skill at all → confused-state
#   check is a no-op (the [ -d ] guard short-circuits before reaching
#   the same-version compare).
[ -d .claude/skills/add-observability ] && { echo "fixture 01 should have no vendored skill"; exit 1; }

# Pre-flight #3: claude CLI present on the host (sandbox uses real PATH;
# we don't enforce here because CI hosts may not have it. The migration's
# `requires.tool.claude.verify` covers this orthogonally.)

# Step 1 idempotency: no vendored copy → already "applied" (test ! -e)
test ! -e .claude/skills/add-observability \
  || { echo "STEP 1 idempotency wrong (vendored copy should be absent)"; exit 1; }
# i.e. Step 1 is a no-op for this fixture — that's the correct behavior.

# Step 2 idempotency: no observability: block → NEEDS to apply (chain init)
grep -q '^observability:' CLAUDE.md \
  && { echo "STEP 2 idempotency wrong (no observability metadata expected)"; exit 1; }

# Step 3 idempotency: version still 1.11.0, NEEDS to apply (bump to 1.12.0)
grep -q '^version: 1.12.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 3 idempotency wrong (version still 1.11.0)"; exit 1; }

echo "fixture 01 — pre-flight passes; Step 1 already-applied (no vendored); Steps 2-3 need to apply"
