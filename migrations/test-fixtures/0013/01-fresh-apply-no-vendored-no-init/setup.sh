#!/bin/sh
# Fixture 01 — fresh apply (before state): project at v1.11.0, NO
# project-local vendored skill, NO observability metadata.
# Pre-flight passes; all 3 steps need to apply.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
# Nothing else — canonical clean v1.11.0 project, never ran init.
