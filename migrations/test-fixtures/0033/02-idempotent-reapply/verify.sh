#!/usr/bin/env bash
# Applying twice must converge, not accumulate. The real hazard is Step 2: the
# splice matches on a heading that the canonical section RE-EMITS, so a second
# run must replace the section it just wrote rather than nest another copy.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

_sect() {
  awk -v h="## Superpowers Integration Hooks" '
    $0 == h { inb=1; print; next }
    inb && /^## / { inb=0 }
    inb { print }' "$1"
}

. "$FIXTURES_ROOT/common-apply.sh"
first_wf="$(cat .claude/claude-md/workflow.md)"
first_cfg="$(cat .claude/workflow-config.md)"

# Every step's idempotency check must now be POSITIVE.
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
cmp -s "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" .claude/claude-md/workflow.md \
  || fail "step 1 idempotency check negative after apply"
cmp -s <(_sect "$SCAFFOLDER/setup/snapshot/workflow-config.md") <(_sect .claude/workflow-config.md) \
  || fail "step 2 idempotency check negative after apply"
cmp -s "$SCAFFOLDER/setup/snapshot/agentic-apps-workflow-SKILL.md" \
       .claude/skills/agentic-apps-workflow/SKILL.md \
  || fail "step 3 idempotency check negative after apply"

. "$FIXTURES_ROOT/common-apply.sh"

[ "$first_wf" = "$(cat .claude/claude-md/workflow.md)" ] \
  || fail "workflow.md drifted on reapply"
[ "$first_cfg" = "$(cat .claude/workflow-config.md)" ] \
  || { echo "workflow-config.md drifted on reapply:"; diff <(printf '%s\n' "$first_cfg") .claude/workflow-config.md; exit 1; }

n=$(grep -c '^## Superpowers Integration Hooks$' .claude/workflow-config.md)
[ "$n" = "1" ] || fail "reapply duplicated the hooks section ($n copies)"

. "$FIXTURES_ROOT/common-verify.sh"
echo OK
