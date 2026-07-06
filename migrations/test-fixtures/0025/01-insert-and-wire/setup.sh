#!/bin/sh
# Fixture 01 — BEFORE: project at v2.2.0 with a normal .planning/config.json
# (hooks block, no knowledge_capture) and a skill without the ritual-tail
# section. The typical fleet state 0025 upgrades.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

mkdir -p .planning
cat > .planning/config.json <<'EOF_CFG'
{
  "hooks": {
    "context_warnings": true
  }
}
EOF_CFG
