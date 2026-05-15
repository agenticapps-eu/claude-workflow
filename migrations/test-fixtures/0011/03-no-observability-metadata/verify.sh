#!/bin/sh
# Pre-flight check #1 must fail. Migration would abort.
set -eu

if grep -q '^observability:' CLAUDE.md; then
  echo "FAIL: observability block exists in fixture — pre-flight 1 would pass when it should fail"
  exit 1
fi

# Confirm: NO migration side-effects have happened (the test would never have
# gotten past pre-flight to produce them).
test -e .github/workflows/observability.yml && { echo "FAIL: workflow file created despite pre-flight abort"; exit 1; }
test -e .observability/baseline.json        && { echo "FAIL: baseline created despite pre-flight abort"; exit 1; }

echo "fixture 03 — pre-flight 1 correctly fails (no observability: block)"
