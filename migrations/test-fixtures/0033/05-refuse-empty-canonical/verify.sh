#!/usr/bin/env bash
# The scaffolder's canonical section extracts EMPTY (heading renamed upstream).
# Step 2 must abort with exit 3 and leave the consumer's file untouched — the
# unguarded splice deleted the section and its heading, putting nothing back,
# which left the project unpatchable on re-run. Reproduced before the guard.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

before="$(cat .claude/workflow-config.md)"
grep -q '^## Superpowers Integration Hooks$' .claude/workflow-config.md \
  || fail "PRE: fixture should carry the hooks heading"

# common-apply.sh exits 3 from Step 2; run it in a subshell so this script can
# inspect the aftermath rather than dying with it.
( . "$FIXTURES_ROOT/common-apply.sh" ) >/tmp/0033-05.out 2>&1
rc=$?

[ "$rc" -eq 3 ] || fail "expected the refusal exit 3, got $rc"
grep -q 'refusing to splice' /tmp/0033-05.out || fail "refusal was silent (no explanation printed)"
[ "$before" = "$(cat .claude/workflow-config.md)" ] \
  || fail "the consumer's workflow-config.md was modified despite the refusal"
grep -q '^## Superpowers Integration Hooks$' .claude/workflow-config.md \
  || fail "the hooks heading was deleted — the exact data loss the guard prevents"
echo OK
exit 3
