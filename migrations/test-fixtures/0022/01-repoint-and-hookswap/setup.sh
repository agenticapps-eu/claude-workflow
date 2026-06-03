#!/bin/sh
# Fixture 01 — repoint + hookswap (BEFORE state): project at v1.20.0, obs skill
# PRESENT in $HOME, CLAUDE.md still names add-observability, prompt-type Stop hook.
# Pre-flight passes; Steps 1-4 all need to apply.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
