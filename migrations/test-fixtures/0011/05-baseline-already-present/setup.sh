#!/bin/sh
# Fixture 05 — pre-existing .observability/baseline.json at v0.3.0.
# Step 2 idempotency check should pass (no rewrite); other steps still need apply.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Drop in a v0.3.0 baseline (Step 2 idempotency catches it)
mkdir -p .observability
cat > .observability/baseline.json <<'EOF_BL'
{
  "spec_version": "0.3.0",
  "scanned_at": "2026-05-15T00:00:00Z",
  "scanned_commit": "0000000000000000000000000000000000000001",
  "module_roots": [],
  "counts": {"conformant": 0, "high_confidence_gaps": 0, "medium_confidence_findings": 0, "low_confidence_findings": 0},
  "high_confidence_gaps_by_checklist": {"C1": 0, "C2": 0, "C3": 0, "C4": 0},
  "policy_hash": "sha256:0000000000000000000000000000000000000000000000000000000000000000"
}
EOF_BL
