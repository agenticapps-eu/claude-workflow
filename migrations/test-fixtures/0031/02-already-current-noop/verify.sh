#!/bin/sh
# Verify 0031 Step 1 is a true no-op when the installed engine already
# matches the vendored source: the idempotency check passes on both an
# initial run AND a re-run, and the file is never touched.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0031/common-verify.sh"

VENDORED="$HOME/.claude/skills/agenticapps-workflow/setup/snapshot/hooks/gitnexus-reindex.cjs"

cmp -s "$VENDORED" .claude/hooks/gitnexus-reindex.cjs || {
  echo "FAIL: fixture setup did not produce an engine identical to the"
  echo "      vendored source — this fixture cannot exercise the"
  echo "      already-current arm of the idempotency check."
  exit 1
}

before_sum="$(cksum .claude/hooks/gitnexus-reindex.cjs)"

check_step1_idempotent || {
  echo "FAIL: idempotency check refused an engine already identical to the"
  echo "      vendored source (first run)"
  exit 1
}
check_step1_idempotent || {
  echo "FAIL: idempotency check refused an engine already identical to the"
  echo "      vendored source (second run) — not stably idempotent"
  exit 1
}

[ "$before_sum" = "$(cksum .claude/hooks/gitnexus-reindex.cjs)" ] || {
  echo "FAIL: the idempotency check itself mutated the engine file"
  exit 1
}

echo "OK: already-current engine reports idempotent (0) on two consecutive"
echo "    runs; file never touched"
exit 0
