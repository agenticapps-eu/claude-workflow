#!/usr/bin/env bash
# Hook 7 — OpenSpec Change Gate (PreToolUse)
#
# The spec §18 retarget of the ADR-0018 multi-AI plan-review gate. Same hook
# slot, same mechanism (PreToolUse payload on stdin, exit 2 = block), new
# predicate: instead of "a *-PLAN.md without a *-REVIEWS.md" it now asks
#
#   is there an active OpenSpec change, and if so does it BOTH
#     (1) pass `openspec validate --all`, and
#     (2) carry REVIEWS.md with >= 2 independent reviewers?
#
# This file is deliberately a SHIM, not an implementation. The enforcement
# surface is ONE host-agnostic script shared by every agent (claude, codex,
# opencode, pi) and by the git pre-commit + CI floor, so there is exactly one
# place where the rule lives and exactly one place to test. See spec §18 and
# docs/WORKFLOW.md.
#
# Resolution order:
#   1. $OPENSPEC_GATE                              (explicit override)
#   2. ~/.agenticapps/bin/openspec-change-gate.sh  (the global install)
#   3. <repo>/bin/openspec-change-gate.sh          (scaffolder checkout)
#
# Fires on PreToolUse matcher: Edit|Write|MultiEdit|NotebookEdit
# Exit 2 = BLOCK; Exit 0 = ALLOW.
#
# Override (emergency, logged):  export GSD_SKIP_REVIEWS=1
# Stricter posture (opt-in):     export OPENSPEC_GATE_STRICT=1   # no code without a change
#
# FAIL-OPEN if the gate cannot be located: a missing global install must not
# brick every edit in a session. The pre-commit + CI floor still catches the
# commit, which is the guarantee that actually matters (§18 — a PreToolUse
# hook cannot gate its own installing session anyway).

GATE="${OPENSPEC_GATE:-$HOME/.agenticapps/bin/openspec-change-gate.sh}"
if [ ! -x "$GATE" ]; then
  GATE="$(git rev-parse --show-toplevel 2>/dev/null)/bin/openspec-change-gate.sh"
fi
[ -x "$GATE" ] || exit 0

exec "$GATE"
