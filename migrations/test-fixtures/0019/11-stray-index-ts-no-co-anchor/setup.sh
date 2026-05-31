#!/usr/bin/env bash
# Fixture 11 — negative case. Plants index.ts files in dist/ and elsewhere
# WITHOUT sibling middleware.ts co-anchors. After Plan 02 ships the
# pre-classify filter, engine must NOT classify these as wrappers (no
# cron-monitor.ts written there). Mitigates Pitfall 1 / T-25-04.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# No real wrapper — just stray index.ts files in build/dist locations.
mkdir -p dist src/utils
cat > dist/index.ts <<'EOF'
// Build output — not a wrapper.
export const bundled = true;
EOF
cat > src/utils/index.ts <<'EOF'
// Re-export barrel — not a wrapper.
export * from "./helpers";
EOF

# Project at v1.17.0 with no observability wrapper at all — engine should
# bump version to 1.18.0 (no-wrapper path) and exit 0 without writing
# cron-monitor.ts ANYWHERE.
