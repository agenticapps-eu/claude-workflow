#!/bin/sh
# Verify 0031 Step 1 re-syncs an old (pre-`--skip-agents-md`) engine: the
# idempotency check must refuse the stale bytes, Apply must overwrite them
# with the vendored engine (byte-identical, executable bit preserved), and a
# re-run must converge (idempotency check now passes).
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0031/common-verify.sh"

VENDORED="$HOME/.claude/skills/agenticapps-workflow/setup/snapshot/hooks/gitnexus-reindex.cjs"

# Sanity: the BEFORE state really is the old engine, not the vendored one —
# otherwise this fixture would vacuously pass no matter what Apply does.
cmp -s "$VENDORED" .claude/hooks/gitnexus-reindex.cjs && {
  echo "FAIL: fixture setup produced an engine already identical to the"
  echo "      vendored source — this fixture cannot exercise a re-sync."
  exit 1
}
grep -q -- '--skip-agents-md' .claude/hooks/gitnexus-reindex.cjs && {
  echo "FAIL: fixture setup's 'old' engine already carries --skip-agents-md"
  exit 1
}

check_step1_idempotent && { echo "FAIL: idempotency check passed on the OLD (stale) engine"; exit 1; }

apply_step1

cmp -s "$VENDORED" .claude/hooks/gitnexus-reindex.cjs || {
  echo "FAIL: after apply_step1, the installed engine is not byte-identical"
  echo "      to the vendored source. Diff:"
  diff "$VENDORED" .claude/hooks/gitnexus-reindex.cjs || true
  exit 1
}

grep -q -- '--skip-agents-md' .claude/hooks/gitnexus-reindex.cjs || {
  echo "FAIL: re-synced engine does not carry --skip-agents-md"
  exit 1
}

[ -x .claude/hooks/gitnexus-reindex.cjs ] || {
  echo "FAIL: re-synced engine is not executable"
  exit 1
}

check_step1_idempotent || {
  echo "FAIL: re-running the idempotency check after apply_step1 still"
  echo "      reports the engine as stale — 0031 does not converge."
  exit 1
}

echo "OK: OLD engine re-synced to the vendored (--skip-agents-md) bytes;"
echo "    executable bit preserved; re-run idempotency check converges"
exit 0
