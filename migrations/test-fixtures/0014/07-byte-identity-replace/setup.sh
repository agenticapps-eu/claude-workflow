#!/bin/sh
# Fixture 07 — byte-identity regression test. Unlike fixtures 01-06,
# which only verify pre-flight + step-idempotency-check behavior on the
# BEFORE state, this fixture actually executes the migration's Step 1
# apply bash (both insert and replace paths) and asserts the §11 block
# in the resulting CLAUDE.md is byte-identical to the vendored canonical
# block.
#
# Added after the initial GREEN commit caught a bug in the replace
# awk: the naïve `/^## /` terminator fired on the §11 block's own
# heading line, leaving the old block body in place after the new
# block was inserted. The 1-6 fixtures missed this because they
# don't exercise the apply path.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Create a "stale" CLAUDE.md with a §11 block at @0.4.0-pre provenance,
# plus a trailing `## Workflow` section (the typical post-migration-0009
# shape — `## Workflow` is the natural block terminator the replace
# logic must respect).
{
  echo ""
  echo "<!-- spec-source: agenticapps-workflow-core@0.4.0-pre §11 -->"
  cat "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
  echo ""
  echo "## Workflow"
  echo ""
  echo "This is a trailing section that the replace logic must not delete."
} >> CLAUDE.md
