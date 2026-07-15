#!/bin/sh
# Verify rollback_step1 is an honest reporting no-op after a heal: it returns
# 0, it does NOT restore the pre-apply (stale) bytes, it leaves the file
# byte-identical to its post-apply (healed) state, and it does not terminate
# the calling shell.
#
# On what actually proves that last clause: NOT the `$(...)`-captured call
# below, and NOT this script reaching its final "OK" line. Command
# substitution is itself a subshell, so it swallows an `exit` regardless of
# whether the harness is correct — and a premature `exit 0` is
# indistinguishable from normal completion by exit status alone, so an
# exit-code comparison cannot see it either. Both of those "proofs" were
# tried and shown to be unfailable. The clause is bound instead by the bare
# call further down, guarded by an EXIT trap. See the comment there.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

apply_step1
after="$(cat CLAUDE.md)"

set +e
rollback_out="$(rollback_step1 2>&1)"
rc=$?
set -e

# (This echo is NOT a proof — the $(...) capture above would have swallowed an
# exit anyway. It is a trace line. The real bind is the bare call below.)
echo "TRACE: rollback_step1 returned via command substitution (exit $rc)"

[ "$rc" -eq 0 ] || {
  echo "FAIL: rollback_step1 returned non-zero ($rc): $rollback_out"
  exit 1
}

# A BARE call — NOT wrapped in `$(...)` — because command substitution is
# itself a subshell and would swallow any `exit` regardless of whether
# rollback_step1's own subshell contract holds. This is what actually binds
# that contract: if rollback ever `exit`s from a brace-group harness (the
# original bug: an eval'd Rollback block's `exit 0` silently terminating the
# calling fixture with a vacuous PASS), the bare call below terminates THIS
# process before reaching the sentinel echo that follows it.
#
# That alone is not enough to turn the fixture red: a premature `exit 0`
# produces the exact same OS-level exit status (0) as running to completion,
# and expected-exit for this fixture is 0 either way — exit-code comparison
# cannot tell "died early" from "finished normally". The EXIT trap closes
# that gap: it is armed only for the duration of the bare call, and if the
# call ends the process while it is still armed, the trap itself overrides
# the exit status to 1 before the process actually dies. On the correct
# (subshell) path the bare call returns normally, the trap is disarmed
# immediately after, and the process later exits 0 through the final `exit 0`
# below untouched.
# fd 3 saves the real stdout before the bare call's own `>/dev/null`
# redirection takes it over. If the trap fires, it fires while fd 1 is still
# pointed at /dev/null (the process never returns from the bare call to undo
# that redirection) — writing the FAIL message to fd 1 there would vanish
# silently. fd 3 is what lets the message survive to be seen.
exec 3>&1
_vacuous_pass_guard() {
  echo "FAIL: rollback_step1 terminated the caller before reaching the"    >&3
  echo "      post-call sentinel — THE VACUOUS-PASS BUG: an eval'd Rollback" >&3
  echo "      block's exit propagated through a non-subshell harness and" >&3
  echo "      silently ended this fixture with an unearned PASS."         >&3
  exit 1
}
trap _vacuous_pass_guard EXIT
rollback_step1 >/dev/null 2>&1
trap - EXIT
exec 3>&-
echo "SENTINEL: caller survived a BARE (non-subshell-wrapped) call to rollback_step1"

[ "$after" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: rollback altered the healed file. Rollback must be an honest"
  echo "      reporting no-op, leaving the file byte-identical to its"
  echo "      post-apply (healed) state — NOT restored to the stale BEFORE"
  echo "      state (that restore contract was withdrawn)."
  exit 1
}

echo "OK: rollback_step1 is a reporting no-op (exit 0); file stays"
echo "    byte-identical to its healed post-apply state; caller reached the"
echo "    end of the fixture (sentinel survived)"
exit 0
