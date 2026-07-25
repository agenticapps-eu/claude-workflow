#!/usr/bin/env bash
# A project may register the retired gate and its OWN hook inside one
# PreToolUse entry. Step 3 must remove only our command, never the entry.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

jq -e '[.hooks.PreToolUse[] | select(._hook=="combined")] | length == 1' .claude/settings.json >/dev/null \
  || fail "PRE: fixture must carry a combined hook entry"

. "$FIXTURES_ROOT/common-apply.sh"

jq -e '[.. | .command? // empty | select(test("project-own-audit"))] | length == 1' .claude/settings.json >/dev/null \
  || fail "the project's own hook was deleted along with the retired gate"
jq -e '[.. | .command? // empty | select(test("multi-ai-review-gate"))] | length == 0' .claude/settings.json >/dev/null \
  || fail "the retired gate command survived"

. "$FIXTURES_ROOT/common-verify.sh"
echo OK
