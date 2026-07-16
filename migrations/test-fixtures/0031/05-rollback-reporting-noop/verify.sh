#!/bin/sh
# Verify rollback_step1 is an honest reporting no-op after a re-sync: it
# returns 0, it does NOT restore the pre-apply (old) bytes, it leaves the
# file byte-identical to its post-apply (re-synced) state, and it does not
# terminate the calling shell.
#
# On what actually proves that last clause — ported from 0030's harness note
# verbatim, because the same failure mode applies here: NOT the
# `$(...)`-captured call below, and NOT this script reaching its final "OK"
# line. Command substitution is itself a subshell, so it swallows an `exit`
# regardless of whether the harness is correct — and a premature `exit 0` is
# indistinguishable from normal completion by exit status alone. The clause
# is bound by the bare call further down, guarded by an EXIT trap.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0031/common-verify.sh"

apply_step1
after="$(cat .claude/hooks/gitnexus-reindex.cjs)"

set +e
rollback_out="$(rollback_step1 2>&1)"
rc=$?
set -e

echo "TRACE: rollback_step1 returned via command substitution (exit $rc)"

[ "$rc" -eq 0 ] || {
  echo "FAIL: rollback_step1 returned non-zero ($rc): $rollback_out"
  exit 1
}

# A BARE call — NOT wrapped in `$(...)` — because command substitution is
# itself a subshell and would swallow any `exit` regardless of whether
# rollback_step1's own subshell contract holds. This is what actually binds
# that contract: if rollback ever `exit`s from a brace-group harness, the
# bare call below terminates THIS process before reaching the sentinel echo
# that follows it.
#
# A premature `exit 0` produces the exact same OS-level exit status (0) as
# running to completion, and expected-exit for this fixture is 0 either way
# — exit-code comparison alone cannot tell "died early" from "finished
# normally". The EXIT trap closes that gap: armed only for the duration of
# the bare call, it overrides the exit status to 1 if the process dies while
# it is still armed.
exec 3>&1
_vacuous_pass_guard() {
  echo "FAIL: rollback_step1 terminated the caller before reaching the"    >&3
  echo "      post-call sentinel — THE VACUOUS-PASS BUG: an eval'd"        >&3
  echo "      Rollback block's exit propagated through a non-subshell"     >&3
  echo "      harness and silently ended this fixture with an unearned"    >&3
  echo "      PASS."                                                        >&3
  exit 1
}
trap _vacuous_pass_guard EXIT
rollback_step1 >/dev/null 2>&1
trap - EXIT
exec 3>&-
echo "SENTINEL: caller survived a BARE (non-subshell-wrapped) call to rollback_step1"

[ "$after" = "$(cat .claude/hooks/gitnexus-reindex.cjs)" ] || {
  echo "FAIL: rollback altered the re-synced file. Rollback must be an"
  echo "      honest reporting no-op, leaving the file byte-identical to"
  echo "      its post-apply (re-synced) state — NOT restored to the OLD"
  echo "      pre-apply state (there is no backup mechanism to restore from)."
  exit 1
}

echo "OK: rollback_step1 is a reporting no-op (exit 0); file stays"
echo "    byte-identical to its re-synced post-apply state; caller reached"
echo "    the end of the fixture (sentinel survived)"
exit 0
