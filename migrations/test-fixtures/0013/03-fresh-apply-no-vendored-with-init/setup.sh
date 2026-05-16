#!/bin/sh
# Fixture 03 — project at v1.11.0, NO vendored skill, but init has
# already been run (observability: block exists in CLAUDE.md).
# Step 1 idempotent (no vendored); Step 2 idempotent (init already
# happened); Step 3 NEEDS to apply (version bump).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Append a minimal observability: metadata block to CLAUDE.md.
cat >> CLAUDE.md <<'EOF_OBS'

observability:
  spec_version: 0.3.0
  policy: lib/observability/policy.md
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
EOF_OBS
