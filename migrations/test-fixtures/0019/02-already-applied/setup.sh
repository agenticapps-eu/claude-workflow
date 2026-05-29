#!/usr/bin/env bash
# Fixture 02 — already-applied state: clean v1.17.0 cf-worker fingerprint PLUS
# a pre-existing cron-monitor.ts placeholder. The engine's idempotency check
# (cron-monitor.{ts,go} presence) classifies this root as SKIP_ALREADY → no
# files written, version bump runs, exits 0.
#
# Stores the placeholder bytes + mtime via a sidecar witness file so verify.sh
# can prove "engine did not overwrite".
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_clean_worker "src/lib/observability"

# Placeholder content distinguishable from the production source.
cat > src/lib/observability/cron-monitor.ts <<'EOF_PLACEHOLDER'
// PLACEHOLDER from fixture 02 — engine MUST NOT overwrite this file.
// If the engine clobbered this with the production template, the sentinel
// comment below disappears and verify.sh fails.
export const FIXTURE_02_SENTINEL = "do-not-overwrite";
EOF_PLACEHOLDER

# Record a content hash for the placeholder so verify.sh can confirm bytes
# survived the engine invocation. (mtime is fragile across sandboxes; sha256
# is the durable signal.)
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum src/lib/observability/cron-monitor.ts | awk '{print $1}' > .fixture-02-cron-hash
else
  shasum -a 256 src/lib/observability/cron-monitor.ts | awk '{print $1}' > .fixture-02-cron-hash
fi
