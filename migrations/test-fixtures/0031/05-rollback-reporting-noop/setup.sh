#!/bin/sh
# Fixture 05 — BEFORE: the OLD engine, same as fixture 01. Rollback is
# exercised after a real Apply.
#
# Rollback has no forward inverse (see the migration's Step 1 Rollback
# rationale and 0030's precedent). It must return 0, leave the file
# byte-identical to its post-apply (re-synced) state, and — critically —
# never terminate the calling shell (an `exit` from an eval'd Rollback block
# would silently kill the calling fixture with a vacuous PASS, the exact bug
# 0030's harness note documents at length).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

mkdir -p .claude/hooks
make_old_engine > .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
