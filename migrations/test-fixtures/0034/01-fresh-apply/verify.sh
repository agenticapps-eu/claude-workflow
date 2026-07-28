#!/usr/bin/env bash
# Fresh apply against a 3.1.0 project carrying 0033's correct-but-duplicated copy.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

# PRE: the before-state is the duplication this migration removes.
grep -q '^## 14 Red Flags' .claude/claude-md/workflow.md || fail "PRE: expected a duplicated red-flag block"
grep -q '^## Workflow commitment$' .claude/claude-md/workflow.md || fail "PRE: expected a duplicated commitment ritual"
grep -q 'If you think\.\.\.' .claude/claude-md/workflow.md || fail "PRE: expected a duplicated rationalization table"
grep -q '^> \*\*Authoritative source:' .claude/claude-md/workflow.md && fail "PRE: should not already be the companion"

. "$FIXTURES_ROOT/common-apply.sh"
. "$FIXTURES_ROOT/common-verify.sh"

# The companion still orients — it defers, it does not go blank.
grep -q '/opsx:propose' .claude/claude-md/workflow.md || fail "companion lost the lifecycle entry points"
grep -q 'change-gate' .claude/claude-md/workflow.md || fail "companion lost the §18 gate section"
echo OK
