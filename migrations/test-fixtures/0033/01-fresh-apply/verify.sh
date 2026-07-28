#!/usr/bin/env bash
# Fresh apply against a 3.0.0 project carrying the pre-0033 GSD-teaching payload.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

# PRE: the before-state is the defect this migration exists to fix.
grep -q '/gsd-execute-phase' .claude/claude-md/workflow.md \
  || fail "PRE: expected the GSD-teaching workflow reference"
grep -q '## GSD Workflow Enforcement' .claude/claude-md/workflow.md \
  || fail "PRE: expected the GSD Workflow Enforcement section"
grep -q 'Superpowers + GSD + gstack' .claude/workflow-config.md \
  || fail "PRE: expected the GSD-worded hooks section"
grep -q '^- \*\*Name\*\*: sandbox-repo$' .claude/workflow-config.md \
  || fail "PRE: expected substituted placeholders"

. "$FIXTURES_ROOT/common-apply.sh"
. "$FIXTURES_ROOT/common-verify.sh"

# The retired section is gone, not merely reworded.
grep -q '## GSD Workflow Enforcement' .claude/claude-md/workflow.md \
  && fail "the GSD Workflow Enforcement section survived the re-vendor"

# The project's substituted values are still the project's.
grep -q '^- \*\*Name\*\*: sandbox-repo$' .claude/workflow-config.md \
  || fail "Step 2 clobbered the project's substituted config"
grep -q '^- \*\*Backend\*\*: Go$' .claude/workflow-config.md \
  || fail "Step 2 clobbered the project's tech stack"

# The hooks section really was replaced, not just left alone.
grep -q 'OpenSpec + Superpowers + gstack workflow' .claude/workflow-config.md \
  || fail "Step 2 did not install the canonical hooks section"
echo OK
