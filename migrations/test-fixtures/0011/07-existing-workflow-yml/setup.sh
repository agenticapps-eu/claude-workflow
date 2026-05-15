#!/bin/sh
# Fixture 07 — pre-existing different observability.yml in .github/workflows.
# Step 1 backs it up before overwrite. Test verifies (a) the existing file
# differs from the scaffolder copy (so Step 1 idempotency returns non-zero
# = "needs apply"), and (b) the backup-then-overwrite logic in setup
# transforms to the expected after-state.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Drop in a DIFFERENT pre-existing workflow file.
mkdir -p .github/workflows
cat > .github/workflows/observability.yml <<'EOF_OLD_YML'
# User-customised workflow that pre-dates migration 0011.
name: Custom observability
on:
  push:
    branches: [trunk]   # note: not main!
EOF_OLD_YML

# Simulate Step 1's apply logic (backup + overwrite). This is what the
# migration's Apply block describes; we exercise the shell version of it.
SCAFFOLDER_YML="$HOME/.claude/skills/agenticapps-workflow/add-observability/ci/observability.yml"
if [ -f .github/workflows/observability.yml ] && ! cmp -s "$SCAFFOLDER_YML" .github/workflows/observability.yml; then
  TS="20260515T000000Z"
  cp .github/workflows/observability.yml ".github/workflows/observability.yml.bak.${TS}"
fi
cp "$SCAFFOLDER_YML" .github/workflows/observability.yml
