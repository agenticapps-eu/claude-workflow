#!/bin/sh
# Fixture 01 — fresh install: project at v1.14.0; no symlink at
# $HOME/.claude/skills/ts-declare-first yet. Pre-flight passes; Step 1
# needs to apply (install user-global symlink).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
# Nothing else — clean fresh-install state. Verify confirms the symlink
# is absent and would be created by Step 1.
