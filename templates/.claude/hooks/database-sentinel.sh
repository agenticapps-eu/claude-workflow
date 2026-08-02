#!/usr/bin/env bash
# database-sentinel — shim. Resolves the fleet-shared implementation and hands over.
#
# shim-contract: 1.0.0
#
# This file is a SHIM, not an implementation. Editing it changes nothing about
# what the hook enforces; the implementation lives in agenticapps-workflow-core
# at reference-implementations/project-hooks/database-sentinel.sh and is published to
# ~/.agenticapps/bin/ by install-shared-artifact.sh. See that directory's
# README.md for the contract this file implements.

set -u

HOOK="database-sentinel"

# --- resolution -------------------------------------------------------------
# Two candidates, in order. There is deliberately NO third <repo>/bin/ candidate:
# a repo-local copy is the drift this shim exists to remove, and as a fallback it
# would keep the drift while hiding it on exactly the machines nobody checks.

OVERRIDE_VAR="$(printf '%s' "$HOOK" | tr 'a-z-' 'A-Z_')_OVERRIDE"
OVERRIDE="${!OVERRIDE_VAR-}"
SHARED="$HOME/.agenticapps/bin/$HOOK.sh"

# --- reporting --------------------------------------------------------------
# Exit 1, never 2. Per the host's hook contract, an exit code other than 0 or 2
# is a non-blocking error: the transcript shows a "<hook> hook error" notice
# followed by THE FIRST LINE of stderr, and execution continues. Exit 2 would
# block, which is the one thing an unresolvable shim must not do — these hooks
# are registered on broad matchers, so blocking here blocks every command and
# every edit in the repository rather than the narrow thing the hook guards.
#
# The first line therefore has to carry the whole message. Everything after it
# reaches the debug log only.

report() { printf '%s\n' "$@" >&2; }

# The unresolvable-implementation condition is persistent: on an unprovisioned
# machine it holds on every Bash, Edit and Write, indefinitely. Reporting each
# time is the alarm fatigue this change rejects elsewhere, so it is rate limited
# to once per hour, per hook, per machine.
#
# ONCE PER HOUR, NOT ONCE PER SESSION, and the reason is recorded rather than
# the option dropped silently (task 2.11a): the session identifier exists only
# in the stdin payload — the host exports no session-id environment variable —
# and a shim that reads stdin to find it has consumed the implementation's
# input. An hour approximates a session closely enough to serve, while
# guaranteeing a long session sees the condition more than once.
#
# One marker path, read and written. No tool payload is inspected.
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

# --- candidate 1: the explicit override -------------------------------------
# An override that is set but unusable does NOT fall through to the shared
# install. Falling through would silently ignore an explicit instruction, and
# the operator who set it would never learn it had no effect.
#
# This report is deliberately NOT rate limited (task 2.11c). The override is a
# kill switch: it is the only signal that a hook has been switched off on an
# otherwise healthy machine, and a rate limit adopted to quiet the benign,
# self-correcting condition above must not also silence it.
if [ -n "$OVERRIDE" ]; then
  if [ -x "$OVERRIDE" ]; then
    exec "$OVERRIDE" "$@"
  fi
  report "$HOOK hook: $OVERRIDE_VAR is set to '$OVERRIDE', which is not an executable file — this hook did NOT run, and no fallback was used" \
         "  Unset $OVERRIDE_VAR to use the shared install at $SHARED," \
         "  or point it at an executable implementation."
  exit 1
fi

# --- candidate 2: the shared install ----------------------------------------
if [ -x "$SHARED" ]; then
  exec "$SHARED" "$@"
fi

# --- unresolvable: allow, and report ----------------------------------------
report_rate_limited \
  "$HOOK hook: not installed at $SHARED — this hook did NOT run, and the tool call was allowed" \
  "  This machine is unprovisioned. Run install-shared-artifact.sh from" \
  "  agenticapps-workflow-core to publish the shared implementations." \
  "  Reported at most once per hour per hook; see shim-contract 1.0.0."
exit 1
