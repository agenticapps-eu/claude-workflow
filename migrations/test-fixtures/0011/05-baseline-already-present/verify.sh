#!/bin/sh
# Step 1 idempotency check returns 0; Step 2/3/4 return non-zero.
set -eu

# Step 1: ALREADY APPLIED (baseline pre-existing at v0.3.0)
test -f .observability/baseline.json && jq -e '.spec_version == "0.3.0"' .observability/baseline.json >/dev/null 2>&1 || { echo "FAIL: fixture's pre-existing baseline not recognized by Step 1 idempotency check"; exit 1; }

# Step 2: NEEDS APPLY (no enforcement block yet)
{ grep -q '^  enforcement:' CLAUDE.md && grep -q '^  spec_version: 0.3.0' CLAUDE.md; } && { echo "FAIL: Step 2 reports already-applied"; exit 1; }

# Step 3: NEEDS APPLY (no per-PR enforcement section yet)
{ grep -q '^### Observability enforcement (local)' CLAUDE.md && grep -q 'add-observability scan --since-commit main' CLAUDE.md; } && { echo "FAIL: Step 3 reports already-applied"; exit 1; }

# Step 4: NEEDS APPLY (version still 1.9.3)
grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md && { echo "FAIL: Step 4 reports already-applied"; exit 1; }

echo "fixture 05 — Step 1 correctly recognizes pre-existing baseline; Steps 2/3/4 still need apply"
