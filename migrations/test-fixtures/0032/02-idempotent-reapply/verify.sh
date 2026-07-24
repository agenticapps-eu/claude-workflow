#!/usr/bin/env bash
# Applying twice must converge, not accumulate. The real hazard is Step 3's jq:
# it APPENDS the new binding, so a second run without the filter would duplicate it.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

. "$FIXTURES_ROOT/common-apply.sh"
first=$(jq -S . .claude/settings.json)
firstcfg=$(jq -S . .planning/config.json)

# Every step's idempotency check must now be POSITIVE.
[ -x "$HOME/.agenticapps/bin/openspec-change-gate.sh" ] || fail "step 1 check negative after apply"
[ -x .claude/hooks/openspec-change-gate.sh ] || fail "step 3 check negative after apply"
[ -e .claude/hooks/multi-ai-review-gate.sh ] && fail "step 3 check negative after apply"
jq -e '.lifecycle.validate.change_gate' .planning/config.json >/dev/null || fail "step 5 check negative after apply"

. "$FIXTURES_ROOT/common-apply.sh"
second=$(jq -S . .claude/settings.json)
secondcfg=$(jq -S . .planning/config.json)

[ "$first" = "$second" ] || { echo "settings.json drifted on reapply:"; diff <(echo "$first") <(echo "$second"); exit 1; }
[ "$firstcfg" = "$secondcfg" ] || { echo "config.json drifted on reapply:"; diff <(echo "$firstcfg") <(echo "$secondcfg"); exit 1; }

n=$(jq '[.hooks.PreToolUse[]?.hooks[]?.command? | select(test("openspec-change-gate"))] | length' .claude/settings.json)
[ "$n" = "1" ] || fail "reapply duplicated the gate binding ($n copies)"

. "$FIXTURES_ROOT/common-verify.sh"
echo OK
