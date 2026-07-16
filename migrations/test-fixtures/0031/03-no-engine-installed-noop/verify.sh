#!/bin/sh
# Verify 0031 Step 1 skips cleanly when there is no engine installed at all,
# and — the load-bearing assertion — creates NOTHING. A migration runner is
# expected to never call Apply when the idempotency check returns 0, but this
# fixture also proves the stronger, structural guarantee directly: Step 1's
# Apply block has no `mkdir -p` of its own, so even a stray invocation (a
# hypothetical runner bug) cannot conjure a new install where none existed —
# `cp` into a missing .claude/hooks/ directory simply fails.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0031/common-verify.sh"

[ ! -e .claude/hooks/gitnexus-reindex.cjs ] || {
  echo "FAIL: fixture setup already has an engine installed — this fixture"
  echo "      cannot exercise the no-engine-at-all case."
  exit 1
}

check_step1_idempotent || {
  echo "FAIL: idempotency check refused a project with no engine installed"
  echo "      at all — this must report 'nothing to do', not 'stale'."
  exit 1
}

[ ! -e .claude/hooks/gitnexus-reindex.cjs ] || {
  echo "FAIL: the idempotency check itself created an engine file"
  exit 1
}

# Structural guarantee: a stray call to apply_step1 must not install
# anything either, since Apply has no mkdir -p of its own.
set +e
apply_step1 >/dev/null 2>&1
set -e

[ ! -e .claude/hooks/gitnexus-reindex.cjs ] || {
  echo "FAIL: apply_step1 installed an engine into a project that never"
  echo "      had one — 0031 must never do this (that is 0026's job)."
  exit 1
}
[ ! -d .claude/hooks ] || {
  echo "FAIL: apply_step1 created .claude/hooks/ in a project that never"
  echo "      had one."
  exit 1
}

echo "OK: no-engine project reports idempotent (0); .claude/hooks/ was"
echo "    never created, even under a stray apply_step1 call"
exit 0
