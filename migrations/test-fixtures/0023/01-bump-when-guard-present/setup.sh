#!/bin/sh
# Fixture 01 — BEFORE state: project at v2.0.0 with the injection-guard skill
# installed in $HOME. Pre-flight passes; Step 1's positive anchor (injection_guard:
# block) and Step 2's positive anchor (version 2.1.0) are both ABSENT, so each
# step "needs to apply".
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
