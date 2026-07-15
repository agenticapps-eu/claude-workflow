#!/bin/sh
# Verify rollback_step1 is an honest reporting no-op after a heal: it returns
# 0, it does NOT restore the pre-apply (stale) bytes, it leaves the file
# byte-identical to its post-apply (healed) state, and — the sentinel check
# below — it does not terminate the calling shell. `rollback_step1` runs its
# eval'd block in a subshell (see common-verify.sh's header note), which is
# exactly what makes it safe to call here without killing this script; the
# echo immediately after the call, plus this script actually reaching its
# own final "OK" line, is the proof that survived.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

apply_step1
after="$(cat CLAUDE.md)"

set +e
rollback_out="$(rollback_step1 2>&1)"
rc=$?
set -e

echo "SENTINEL: caller survived the call to rollback_step1 (exit $rc)"

[ "$rc" -eq 0 ] || {
  echo "FAIL: rollback_step1 returned non-zero ($rc): $rollback_out"
  exit 1
}

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
