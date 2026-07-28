#!/usr/bin/env bash
# The hooks section is not always last. Step 2's splice must resume printing at
# the next `## ` heading — a truncate-and-append would silently delete every
# project-owned section below it.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

grep -q '^## Project-owned appendix$' .claude/workflow-config.md \
  || fail "PRE: fixture should carry a trailing project section"

. "$FIXTURES_ROOT/common-apply.sh"
. "$FIXTURES_ROOT/common-verify.sh"

grep -q '^## Project-owned appendix$' .claude/workflow-config.md \
  || fail "Step 2 deleted the project-owned section below the hooks section"
grep -q 'MUST survive the re-vendor verbatim' .claude/workflow-config.md \
  || fail "Step 2 truncated the project-owned section's body"

# ...and the hooks section above it really was replaced.
grep -q 'Superpowers + GSD + gstack' .claude/workflow-config.md \
  && fail "the GSD-worded hooks section survived"
grep -q '^## Superpowers Integration Hooks$' .claude/workflow-config.md \
  || fail "the hooks heading went missing"
echo OK
