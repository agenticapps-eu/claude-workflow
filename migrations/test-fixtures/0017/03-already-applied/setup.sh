#!/usr/bin/env bash
# Fixture 03 — already-applied: the single wrapper root already has the
# registry + adapters (migrated on a prior run). Re-running 0017 must be an
# idempotent no-op (no wrapper changes), still exit 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

materialize_applied_worker "src/lib/observability"

# Mark CLAUDE.md as already at v0.4.0 so the idempotent run leaves it alone.
cat > CLAUDE.md <<'EOF'
# Downstream project CLAUDE.md (0017 fixture, already applied)

observability:
  spec_version: 0.4.0
  destinations: { errors: sentry, logs: axiom, analytics: none }
  policy: src/lib/observability/policy.md
  enforcement: { baseline: .observability/baseline.json }
EOF
