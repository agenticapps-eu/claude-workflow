#!/usr/bin/env bash
# openspec-change-gate — shim. Resolves the shared gate and hands over.
#
# shim-contract: 1.0.0
#
# The spec §18 change gate. This file is a SHIM, not an implementation: the
# enforcement surface is ONE host-agnostic script shared by every agent (claude,
# codex, opencode, pi) and by the git pre-commit + CI floor, so the rule lives in
# exactly one place and is tested in exactly one place. See spec §18,
# docs/WORKFLOW.md, and reference-implementations/project-hooks/README.md.
#
# Profile: published-resolution. Core's own .claude/hooks/openspec-change-gate.sh
# is the self-hosting profile and resolves its working-tree copy instead — see
# ADR-0028. Every hook has exactly one self-hosting binder.
#
# WHAT THE GATE BLOCKS ON — one thing.
#
#   `openspec validate --all` is not green.
#
# Reviewer count, verdicts, independence and the trailer are computed and
# REPORTED, never enforced (gate 2.0.0, openspec/specs/change-gate-enforcement).
# An earlier version of this header said the gate asks whether the change
# "carries REVIEWS.md with >= 2 independent reviewers" — it does not, and has
# not since 2.0.0. A blocked edit means a spec delta that does not parse, so fix
# the delta; it never means "go get a review".
#
# Resolution order — TWO candidates.
#   1. $OPENSPEC_GATE                              (explicit override)
#   2. ~/.agenticapps/bin/openspec-change-gate.sh  (the shared install)
#
# There is no third <repo>/bin/ candidate. A repo-local copy is the drift the
# shim exists to remove, and as a fallback it keeps the drift while hiding it on
# exactly the machines nobody checks.
#
# Fires on PreToolUse matcher: Edit|Write|MultiEdit|NotebookEdit
# Exit 2 = BLOCK; Exit 0 = ALLOW; Exit 1 = could not resolve — allow and report.
#
# Override (emergency, logged):  export GSD_SKIP_REVIEWS=1
# Stricter posture (opt-in):     export OPENSPEC_GATE_STRICT=1
#
# FAIL-OPEN AND REPORT if the gate cannot be located. A missing shared install
# must not brick every edit in a session.
#
# WHAT AN UNRESOLVABLE GATE ACTUALLY COSTS — stated correctly, because the
# previous header overstated the backstop. It said "the pre-commit + CI floor
# still catches the commit". On an UNPROVISIONED machine the pre-commit wrapper
# resolves the same absent shared install and fails open too, so **CI is the
# only floor left**. The pre-commit hook backstops a PROVISIONED machine.

set -u

HOOK="openspec-change-gate"
OVERRIDE="${OPENSPEC_GATE-}"
SHARED="$HOME/.agenticapps/bin/openspec-change-gate.sh"

report() { printf '%s\n' "$@" >&2; }

# Rate limited to once per hour, per hook, per machine. The condition is
# persistent on an unprovisioned machine, so reporting every time would put a
# hook-error notice on essentially every edit — the alarm fatigue this change
# rejects elsewhere. Once per session would be better and is unreachable: the
# session id lives only in the stdin payload, which must reach the gate intact.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/agenticapps"
MARKER="$STATE_DIR/$HOOK.unresolved-report"

report_rate_limited() {
  local now last
  now=$(( $(date +%s) / 3600 ))
  last=$(cat "$MARKER" 2>/dev/null) || last=""
  [ "$last" = "$now" ] && return 0
  mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s\n' "$now" > "$MARKER" 2>/dev/null
  report "$@"
}

# Name this host so its own reviews do not count toward the independence
# calculation the gate REPORTS. Retained deliberately: the companion change
# `track-and-conform-plan-review` retires OPENSPEC_GATE_SELF as an identity
# source, and both changes editing this line would conflict.
export OPENSPEC_GATE_SELF="${OPENSPEC_GATE_SELF:-claude}"

# Candidate 1. An override that is set but unusable does NOT fall through — a
# silently ignored explicit instruction is worse than a loud one. Not rate
# limited: this is the kill switch, and for the §18 gate it is a one-variable
# bypass of enforcement at the tool boundary.
if [ -n "$OVERRIDE" ]; then
  if [ -x "$OVERRIDE" ]; then
    exec "$OVERRIDE" "$@"
  fi
  report "$HOOK hook: OPENSPEC_GATE is set to '$OVERRIDE', which is not an executable file — the change gate did NOT run, and no fallback was used" \
         "  Unset OPENSPEC_GATE to use the shared install at $SHARED."
  exit 1
fi

# Candidate 2.
if [ -x "$SHARED" ]; then
  exec "$SHARED" "$@"
fi

report_rate_limited \
  "$HOOK hook: not installed at $SHARED — the §18 change gate did NOT run, and the edit was allowed" \
  "  On this machine the git pre-commit wrapper resolves the same absent install" \
  "  and also fails open, so CI is the only remaining floor. Run" \
  "  install-shared-artifact.sh from agenticapps-workflow-core." \
  "  Reported at most once per hour; see shim-contract 1.0.0."
exit 1
