#!/usr/bin/env bash
# Applying twice must converge, not accumulate.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }
SCAFFOLDER=~/.claude/skills/agenticapps-workflow

. "$FIXTURES_ROOT/common-apply.sh"
first="$(cat .claude/claude-md/workflow.md)"

cmp -s "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" .claude/claude-md/workflow.md \
  || fail "step 1 idempotency check negative after apply"
grep -q '^version: 3.2.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || fail "step 2 idempotency check negative after apply"

. "$FIXTURES_ROOT/common-apply.sh"
[ "$first" = "$(cat .claude/claude-md/workflow.md)" ] || fail "workflow.md drifted on reapply"

n=$(grep -c '^> \*\*Authoritative source:' .claude/claude-md/workflow.md)
[ "$n" = "1" ] || fail "reapply duplicated the companion header ($n copies)"

. "$FIXTURES_ROOT/common-verify.sh"
echo OK
