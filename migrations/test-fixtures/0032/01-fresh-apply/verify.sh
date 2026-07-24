#!/usr/bin/env bash
# Fresh apply against a 2.9.0 project carrying the full pre-3.0.0 payload.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

# PRE: the before-state is what we think it is.
[ -x .claude/hooks/multi-ai-review-gate.sh ] || fail "PRE: expected the old gate"
[ -e .claude/hooks/gitnexus-reindex.cjs ]    || fail "PRE: expected the gitnexus engine"
jq -e '.hooks.pre_execute_gates.multi_ai_plan_review' .planning/config.json >/dev/null \
  || fail "PRE: expected a 0.x-shaped config"

# Step 1's idempotency check must be NEGATIVE before apply.
[ -x "$HOME/.agenticapps/bin/openspec-change-gate.sh" ] && fail "PRE: gate already installed"

. "$FIXTURES_ROOT/common-apply.sh"
. "$FIXTURES_ROOT/common-verify.sh"

# The shim actually resolves to the installed gate and answers the truth table.
out=$(printf '{"tool":"Edit","tool_input":{"file_path":"src/x.ts"}}' \
        | bash .claude/hooks/openspec-change-gate.sh 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "no active change must ALLOW (exit 0), got $rc: $out"
echo OK
