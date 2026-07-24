#!/usr/bin/env bash
# Steps 3 and 4 REBUILD the PreToolUse / PostToolUse arrays. The edit must be
# surgical: only the retargeted gate and the gitnexus binding may change. Any
# other hook the project registered has to come through byte-identical.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

sentinel_before=$(jq -S '[.hooks.PreToolUse[] | select(._hook | test("Database Sentinel"))]' .claude/settings.json)
[ "$(printf '%s' "$sentinel_before" | jq 'length')" = "1" ] || fail "PRE: expected the extra PreToolUse hook"
normalize_before=$(jq -S '[.hooks.PostToolUse[] | select(._hook | test("Normalize"))]' .claude/settings.json)

. "$FIXTURES_ROOT/common-apply.sh"

sentinel_after=$(jq -S '[.hooks.PreToolUse[] | select(._hook | test("Database Sentinel"))]' .claude/settings.json)
normalize_after=$(jq -S '[.hooks.PostToolUse[] | select(._hook | test("Normalize"))]' .claude/settings.json)
[ "$sentinel_before" = "$sentinel_after" ] \
  || { echo "unrelated PreToolUse hook was modified:"; diff <(echo "$sentinel_before") <(echo "$sentinel_after"); exit 1; }
[ "$normalize_before" = "$normalize_after" ] \
  || { echo "unrelated PostToolUse hook was modified:"; diff <(echo "$normalize_before") <(echo "$normalize_after"); exit 1; }

# PreToolUse should now be: the surviving sentinel + the new gate. Nothing else.
[ "$(jq '[.hooks.PreToolUse[]] | length' .claude/settings.json)" = "2" ] \
  || fail "unexpected PreToolUse entry count after retarget"

. "$FIXTURES_ROOT/common-verify.sh"
echo OK
