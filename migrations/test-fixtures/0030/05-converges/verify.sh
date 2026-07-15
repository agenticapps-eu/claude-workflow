#!/bin/sh
# Verify 0030 converges: a healed block reports in-sync, and a second apply
# is a byte-identical no-op.
#
# NOTE: this fixture is the convergence proof, and is deliberately NOT the
# fixture that catches a region mis-pinned to the terminator line (T-1)
# instead of the last non-blank line (E). Convergence is the one property a
# T-1 region DOES satisfy: it converges, and its extraction of an already
# in-sync file does equal the mirror — so this fixture passes under T-1 while
# the separator blank line before the next `## ` heading is silently deleted.
#
# What catches T-1 is any assertion about bytes OUTSIDE the block region:
# fixture 01 primarily (the deleted separator is a fifth change on top of the
# four blank-line insertions), and fixture 02 secondarily — not via its
# idempotency check, which under T-1 correctly reports "in sync", but because
# 02 does a FORCED apply that still consumes the separator. Both were proven
# by running them against a deliberately T-1-mutated copy of the migration
# (see task-3-report.md). Do not write "only fixture 01" here: that claim has
# been made and refuted four times on this branch.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

apply_step1
check_step1_idempotent || { echo "FAIL: 0030 did not converge — a healed block still reports out-of-sync"; exit 1; }
after="$(cat CLAUDE.md)"
apply_step1
[ "$after" = "$(cat CLAUDE.md)" ] || { echo "FAIL: second apply churned a healed file"; exit 1; }
echo "OK: heals, then converges to a stable byte-identical state"
exit 0
