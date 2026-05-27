#!/usr/bin/env bash
# Fixture 01 — cparx shape: a Go backend + a React frontend, BOTH with
# un-modified (template-byte-identical) wrappers. Both roots are clean →
# both migrate; CLAUDE.md observability block rewritten to v0.4.0. Exit 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Go backend wrapper at internal/observability/observability.go
materialize_clean_go "internal/observability"

# React frontend wrapper at src/lib/observability/index.ts
materialize_clean_react "src/lib/observability"
