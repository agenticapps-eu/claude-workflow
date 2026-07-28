#!/usr/bin/env bash
# agenticapps-dashboard removed its workflow.md deliberately. 0034 must not
# install one back — it re-vendors, it never installs.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

[ -e .claude/claude-md/workflow.md ] && fail "PRE: fixture should start without workflow.md"

. "$FIXTURES_ROOT/common-apply.sh"

[ -e .claude/claude-md/workflow.md ] && fail "Step 1 installed a file into a project that had none"

# Step 2 still runs: the version stamp is not conditional on Step 1.
. "$FIXTURES_ROOT/common-verify.sh"
echo OK
