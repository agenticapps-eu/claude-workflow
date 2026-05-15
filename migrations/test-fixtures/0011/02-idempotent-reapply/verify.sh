#!/bin/sh
# After-state assertions: every step's idempotency check returns 0
# (= "already applied — skip").
set -eu

# Step 1 — baseline present + v0.3.0
test -f .observability/baseline.json && jq -e '.spec_version == "0.3.0"' .observability/baseline.json >/dev/null 2>&1 || { echo "STEP 1 not applied or schema bad"; exit 1; }
# Step 2 — enforcement sub-block + spec_version 0.3.0
grep -q '^  enforcement:' CLAUDE.md && grep -q '^  spec_version: 0.3.0' CLAUDE.md || { echo "STEP 2 not applied"; exit 1; }
# Step 3 — per-PR enforcement section
grep -q '^### Observability enforcement (local)' CLAUDE.md && grep -q 'add-observability scan --since-commit main' CLAUDE.md || { echo "STEP 3 not applied"; exit 1; }
# Step 4 — version bump
grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "STEP 4 not applied"; exit 1; }

# Schema-strict assertions on baseline.json (matches PLAN T14 ledger row)
jq -e '
  .spec_version == "0.3.0" and
  (.scanned_commit | test("^[a-f0-9]{40}$")) and
  (.policy_hash    | test("^sha256:[a-f0-9]{64}$"))
' .observability/baseline.json >/dev/null || { echo "STEP 1 baseline.json schema invalid"; exit 1; }

# Confirm: the CI workflow file is NOT installed (v1.10.0 ships local-only)
test -f .github/workflows/observability.yml && { echo "FAIL: migration installed a CI workflow but v1.10.0 ships local-only"; exit 1; }

echo "fixture 02 — after state correctly reports 'already applied' for all 4 steps; no CI workflow installed (local-only)"
