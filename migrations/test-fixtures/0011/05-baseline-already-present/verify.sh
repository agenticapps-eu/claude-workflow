#!/bin/sh
# Step 2 idempotency check returns 0; Step 1/3/4/5 return non-zero.
set -eu

# Step 2: ALREADY APPLIED
test -f .observability/baseline.json && jq -e '.spec_version == "0.3.0"' .observability/baseline.json >/dev/null 2>&1 || { echo "FAIL: fixture's pre-existing baseline not recognized by Step 2 idempotency check"; exit 1; }

# Step 1: NEEDS APPLY
cmp -s "$HOME/.claude/skills/agenticapps-workflow/add-observability/ci/observability.yml" .github/workflows/observability.yml 2>/dev/null && { echo "FAIL: Step 1 reports already-applied"; exit 1; }

# Step 3: NEEDS APPLY
{ grep -q '^  enforcement:' CLAUDE.md && grep -q '^  spec_version: 0.3.0' CLAUDE.md; } && { echo "FAIL: Step 3 reports already-applied"; exit 1; }

# Step 5: NEEDS APPLY
grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md && { echo "FAIL: Step 5 reports already-applied"; exit 1; }

echo "fixture 05 — Step 2 correctly recognizes pre-existing baseline; other steps still need apply"
