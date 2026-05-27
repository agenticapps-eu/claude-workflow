#!/bin/sh
# Fixture 01 — verify the pre-apply state: every 0018 idempotency check reports
# "needs apply" and pre-flight passes.
set -eu

# Pre-flight: installed version is 1.16.0 → migration accepts it.
grep -q '^version: 1\.16\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT should pass (version 1.16.0)"; exit 1; }
jq empty .planning/config.json || { echo "PRE-FLIGHT config.json must parse"; exit 1; }

# Step 1 idempotency: hook script absent → NEEDS to apply.
test ! -e .claude/hooks/observability-postphase-scan.sh \
  || { echo "STEP 1 idempotency wrong (hook should be absent on fresh install)"; exit 1; }

# Step 2 idempotency: no observability_scan in post_phase → NEEDS to apply.
if jq -e '.hooks.post_phase.observability_scan' .planning/config.json >/dev/null 2>&1; then
  echo "STEP 2 idempotency wrong (observability_scan should be absent on fresh install)"; exit 1
fi

# Step 3 idempotency: version still 1.16.0 → NEEDS to bump.
grep -q '^version: 1\.17\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 3 idempotency wrong (version should still be 1.16.0)"; exit 1; }

echo "fixture 01 — pre-flight passes; all three steps need to apply"
