#!/bin/sh
# Fixture 03 — BEFORE: stale block, then a `<!-- gitnexus:start -->` region
# with NO `## ` heading between the block and the region marker. The region
# body itself contains a `## Always Do` line, which must NOT be mistaken for
# the block's terminator (the terminator scan already exited at
# `gitnexus:start`, before ever reaching that line).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

{
  printf '# CLAUDE.md\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  make_stale_block
  printf '\n<!-- gitnexus:start -->\n# GitNexus\n\n## Always Do\n- x\n<!-- gitnexus:end -->\n'
} > CLAUDE.md
