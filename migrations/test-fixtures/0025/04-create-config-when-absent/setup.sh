#!/bin/sh
# Fixture 04 — BEFORE: project at v2.2.0 with NO .planning/config.json at all
# (edge case: config was never laid down or was deleted). Step 1 must create
# the file containing only the knowledge_capture block.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
# deliberately: no .planning/config.json
