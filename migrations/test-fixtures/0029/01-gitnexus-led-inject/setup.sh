#!/bin/sh
# Fixture 01 — BEFORE: a gitnexus-LED CLAUDE.md with NO §11 block (state C).
# The first `## ` heading in this file is `## Always Do`, which is INSIDE the
# managed region. This is the exact shape 0014's naive anchor injects into and
# a later `gitnexus analyze` then destroys.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > CLAUDE.md <<'EOF_CLAUDE'
# CLAUDE.md

This file provides guidance to Claude Code.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **demo** (100 symbols).

## Always Do
- MUST run impact analysis before editing any symbol.

## Never Do
- NEVER rename symbols with find-and-replace.
<!-- gitnexus:end -->

## Workflow
Project-specific stuff here.
EOF_CLAUDE
