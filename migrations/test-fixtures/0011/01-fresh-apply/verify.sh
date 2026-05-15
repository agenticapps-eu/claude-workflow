#!/bin/sh
# Verify pre-flight + Step 1-5 idempotency checks behave as expected
# on the BEFORE state (fixture 01). Migration is not yet applied.
set -eu

# Pre-flight checks should ALL pass on a fresh-apply candidate:
grep -q '^observability:' CLAUDE.md || { echo "PRE-FLIGHT 1 should pass (observability block present) but did not"; exit 1; }
test -f lib/observability/policy.md || { echo "PRE-FLIGHT 2 should pass (policy.md present) but did not"; exit 1; }
grep -qE '^version: 1\.(9\.3|10\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "PRE-FLIGHT 3 should pass (version 1.9.3) but did not"; exit 1; }
command -v claude >/dev/null || { echo "PRE-FLIGHT 4 (claude) should pass — stub missing?"; exit 1; }

# Each step's idempotency check should return NON-ZERO (= "needs to apply"):
# Step 1
cmp -s "$HOME/.claude/skills/agenticapps-workflow/add-observability/ci/observability.yml" .github/workflows/observability.yml 2>/dev/null && { echo "STEP 1 idempotency wrong: reports already-applied on before state"; exit 1; }
# Step 2
{ test -f .observability/baseline.json && jq -e '.spec_version == "0.3.0"' .observability/baseline.json >/dev/null 2>&1; } && { echo "STEP 2 idempotency wrong"; exit 1; }
# Step 3
{ grep -q '^  enforcement:' CLAUDE.md && grep -q '^  spec_version: 0.3.0' CLAUDE.md; } && { echo "STEP 3 idempotency wrong"; exit 1; }
# Step 4
grep -q 'add-observability scan --since-commit main' CLAUDE.md && { echo "STEP 4 idempotency wrong"; exit 1; }
# Step 5
grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md && { echo "STEP 5 idempotency wrong"; exit 1; }

echo "fixture 01 — before state correctly reports 'needs to apply' for all 5 steps"
