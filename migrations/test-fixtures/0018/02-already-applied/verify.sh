#!/bin/sh
# Fixture 02 — verify the applied state: every 0018 idempotency check returns
# "applied", post-checks hold, and the hook honours its advisory contract.
set -eu

# Step 1 idempotency: hook present + executable → no-op.
test -x .claude/hooks/observability-postphase-scan.sh \
  || { echo "STEP 1 idempotency wrong (hook should be installed + executable)"; exit 1; }

# Step 2 idempotency: observability_scan wired into post_phase → no-op.
jq -e '.hooks.post_phase.observability_scan' .planning/config.json >/dev/null \
  || { echo "STEP 2 idempotency wrong (observability_scan should be present)"; exit 1; }

# Post-checks: advisory contract is encoded in the wiring.
jq -e '.hooks.post_phase.observability_scan.enabled == true' .planning/config.json >/dev/null \
  || { echo "post-check: observability_scan must be enabled"; exit 1; }
jq -e '.hooks.post_phase.observability_scan.blocking == false' .planning/config.json >/dev/null \
  || { echo "post-check: observability_scan must be non-blocking (advisory)"; exit 1; }
jq -e '.hooks.post_phase.observability_scan.programmatic_hook == ".claude/hooks/observability-postphase-scan.sh"' .planning/config.json >/dev/null \
  || { echo "post-check: programmatic_hook path must point at the installed hook"; exit 1; }

# Step 3 idempotency: version bumped to 1.17.0 → no-op.
grep -q '^version: 1\.17\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 3 idempotency wrong (version should be 1.17.0)"; exit 1; }

# Advisory contract: the installed hook must exit 0 even with no baseline
# (project hasn't adopted enforcement). It prints one explicit line and stops.
out=$(bash .claude/hooks/observability-postphase-scan.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] || { echo "hook must exit 0 without a baseline (got $rc)"; exit 1; }
printf '%s' "$out" | grep -q 'no .observability/baseline.json' \
  || { echo "hook should print an explicit no-baseline notice"; exit 1; }

echo "fixture 02 — all steps applied; idempotency no-op; hook advisory contract holds"
