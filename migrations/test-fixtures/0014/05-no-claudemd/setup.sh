#!/bin/sh
# Fixture 05 — no CLAUDE.md: project at v1.12.0, no CLAUDE.md at all
# (un-scaffolded host project). Step 1 takes the permissive no-op path
# (no file to inject into; emit informational message; continue). Step 2
# still applies (version bump).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Delete the CLAUDE.md that common-setup created. This fixture simulates
# the un-scaffolded edge case (paired with migration 0013's "no observability
# block" permissive idiom).
rm -f CLAUDE.md
