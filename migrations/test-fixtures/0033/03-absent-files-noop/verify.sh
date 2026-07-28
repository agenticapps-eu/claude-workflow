#!/usr/bin/env bash
# A project that never vendored these documents (or removed them deliberately —
# agenticapps-dashboard has) must come out the other side WITHOUT them. 0033
# re-vendors; installing a first copy is 0000/0009's job.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

[ -e .claude/claude-md/workflow.md ] && fail "PRE: fixture should start without workflow.md"
[ -e .claude/workflow-config.md ]    && fail "PRE: fixture should start without workflow-config.md"

. "$FIXTURES_ROOT/common-apply.sh"

[ -e .claude/claude-md/workflow.md ] && fail "Step 1 installed a file into a project that had none"
[ -e .claude/workflow-config.md ]    && fail "Step 2 installed a file into a project that had none"

# Step 3 still runs: the version stamp is not conditional on the other two.
. "$FIXTURES_ROOT/common-verify.sh"
echo OK
