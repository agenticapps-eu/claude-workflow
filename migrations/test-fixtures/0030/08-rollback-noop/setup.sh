#!/bin/sh
# Fixture 08 — BEFORE: the stale block, followed by a `## ` heading.
#
# AMENDED (post Task-2-review): Step 1 has no forward inverse — the
# pre-migration bytes are not recoverable from the post-migration file, and
# restoring them would re-introduce the exact defect 0030 exists to fix. The
# `.0030.bak` restore idiom is gone. Rollback is now an honest REPORTING
# no-op: it must return 0, leave the file byte-identical to its post-apply
# (healed) state, and — critically — never terminate the calling shell (a
# previous bug had Rollback `exit 0` from inside an eval'd block, which
# silently killed the calling fixture with a vacuous PASS before it ever
# reached its own assertions).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  make_stale_block
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
