#!/bin/sh
# Fixture 01 — fresh apply (before state).
# Baseline v1.9.3 project with observability metadata at 0.2.1, no
# .github/workflows/observability.yml, no .observability/.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
# Nothing else — the common-setup leaves us in the canonical before state.
