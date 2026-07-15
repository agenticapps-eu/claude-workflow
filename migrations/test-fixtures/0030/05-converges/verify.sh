#!/bin/sh
# Verify 0030 converges: a healed block reports in-sync, and a second apply
# is a byte-identical no-op.
#
# NOTE: this fixture is the convergence proof, and is deliberately NOT the
# fixture that catches a region mis-pinned to the terminator line (T-1)
# instead of the last non-blank line (E). A T-1-pinned region converges too
# — it passes this fixture — while silently deleting the separator blank
# line before the next `## ` heading. That is caught only by fixture 01's
# whole-file diff assertion, proven by running fixture 01 against a
# deliberately T-1-mutated copy of the migration (see task-3-report.md).
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

apply_step1
check_step1_idempotent || { echo "FAIL: 0030 did not converge — a healed block still reports out-of-sync"; exit 1; }
after="$(cat CLAUDE.md)"
apply_step1
[ "$after" = "$(cat CLAUDE.md)" ] || { echo "FAIL: second apply churned a healed file"; exit 1; }
echo "OK: heals, then converges to a stable byte-identical state"
exit 0
