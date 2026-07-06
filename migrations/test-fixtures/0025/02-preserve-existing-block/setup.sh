#!/bin/sh
# Fixture 02 — BEFORE: project at v2.2.0 whose .planning/config.json ALREADY
# carries a user-configured knowledge_capture block (opted out, custom note).
# Step 1's idempotency anchor is positive -> the insert must not touch it.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

mkdir -p .planning
cat > .planning/config.json <<'EOF_CFG'
{
  "hooks": {
    "context_warnings": true
  },
  "knowledge_capture": {
    "enabled": false,
    "note": "/custom/vault/notes/my-repo.md"
  }
}
EOF_CFG
