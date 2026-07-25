#!/usr/bin/env bash
# A project that never installed GitNexus must survive Step 4 untouched — the
# rm -f / jq filter has to be a clean no-op, not an error or an empty PostToolUse.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

[ -e .claude/hooks/gitnexus-reindex.cjs ] && fail "PRE: fixture must have no gitnexus"
before=$(jq '[.hooks.PostToolUse[]] | length' .claude/settings.json)
[ "$before" = "1" ] || fail "PRE: expected 1 PostToolUse entry, got $before"

. "$FIXTURES_ROOT/common-apply.sh"

after=$(jq '[.hooks.PostToolUse[]] | length' .claude/settings.json)
[ "$after" = "1" ] || fail "Step 4 dropped an unrelated PostToolUse entry ($before -> $after)"
jq -e '[.hooks.PostToolUse[]?.hooks[]?.command? | select(test("normalize-claude-md"))] | length == 1' \
  .claude/settings.json >/dev/null || fail "the normalize-claude-md hook was lost"

. "$FIXTURES_ROOT/common-verify.sh"
echo OK
