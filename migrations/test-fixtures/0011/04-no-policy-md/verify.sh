#!/bin/sh
# Pre-flight #1 passes (observability block present); pre-flight #2 fails.
set -eu

grep -q '^observability:' CLAUDE.md || { echo "FAIL: fixture should keep observability block"; exit 1; }

POLICY_PATH=$(awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}' CLAUDE.md | tr -d '"')
POLICY_PATH=${POLICY_PATH:-lib/observability/policy.md}
if [ -f "$POLICY_PATH" ]; then
  echo "FAIL: policy.md should not exist in this fixture but does at $POLICY_PATH"
  exit 1
fi

# Confirm: no migration side-effects.
test -e .observability/baseline.json && { echo "FAIL: baseline created despite pre-flight 2 abort"; exit 1; }

echo "fixture 04 — pre-flight 2 correctly fails (policy.md missing at $POLICY_PATH)"
