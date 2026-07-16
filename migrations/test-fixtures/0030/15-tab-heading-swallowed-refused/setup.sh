#!/bin/sh
# Fixture 15 — BEFORE: a STALE block (the same shape fixture 01 heals),
# followed by an ATX heading whose `#` sequence is separated from its text
# by a TAB rather than a space (`##<TAB>User Section`) and one line of user
# data. CommonMark permits a tab (or a space) after the `#` sequence in an
# ATX heading; this migration's terminator, `^## `, requires a literal
# space, so it does not recognize this form — the region scan does not stop
# there, it keeps scanning until the next UNINDENTED `## ` heading (with a
# real space), swallowing the tab-separated heading and the user data
# underneath it into the block region.
#
# Before the blank-line-drift guard, that swallowed content was silently
# replaced along with the stale block. This fixture asserts the guard
# refuses instead, and the user's data survives byte-identical.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  make_stale_block
  printf '\n##\tUser Section\n'
  printf 'This is my important user data that must survive.\n'
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
