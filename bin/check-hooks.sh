#!/usr/bin/env bash
# check-hooks.sh — verify every programmatic hook registered in the project's
# .claude/settings.json is present and executable (and vice versa), that each
# hook is bound to the correct lifecycle event, plus the global
# commitment-reinject hook. The expected hook SET is DERIVED from
# settings.json, never hardcoded — see ADR-0040. The expected EVENT for a
# small number of known load-bearing gates *is* named explicitly below; that
# is a different thing from hardcoding which hooks must exist.
#
# Usage: cd <agenticapps-project> && /path/to/scaffolder/bin/check-hooks.sh
# Exit 0 if all OK; exit 1 if anything missing/misregistered/misrouted.

set -euo pipefail

GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
[ -t 1 ] || { GREEN=""; RED=""; YELLOW=""; RESET=""; }

OK=0
FAIL=0

check_ok()   { echo "  ${GREEN}✓${RESET} $1"; OK=$((OK+1)); }
check_fail() { echo "  ${RED}✗${RESET} $1"; FAIL=$((FAIL+1)); }

echo "AgenticApps programmatic hooks check"
echo "  cwd: $(pwd)"
echo ""

echo "== Project-scoped (.claude/hooks/) =="
# Derive the expected hook set from the project's own settings.json rather than
# a hardcoded list: a newly registered hook must never escape verification.
# (multi-ai-review-gate.sh — the plan-review enforcer — was silently unchecked
# for exactly this reason; ADR-0025 / ADR-0040.)
#
# This whole derivation is defensive on purpose: settings.json can be valid
# JSON (passes `jq empty`) while still having a shape jq's capture() chokes on
# — e.g. a non-string `"command": 123` value. Every jq invocation below is
# guarded so a jq failure degrades to a reported check_fail, never a `set -e`
# abort (which would kill the script before the summary line ever prints).
HOOK_FILES=""
HOOK_FILES_OK=0
if [ -f .claude/settings.json ] && jq empty .claude/settings.json 2>/dev/null; then
  if HOOK_FILES=$(jq -r '
    [.hooks // {} | .[]? | .[]? | .hooks[]? | .command?]
    | map(select(type == "string"))
    | map(capture("(?<f>[A-Za-z0-9._-]+\\.(sh|cjs))")? | .f)
    | map(select(. != null))
    | unique
    | .[]
  ' .claude/settings.json 2>/dev/null); then
    HOOK_FILES_OK=1
  else
    check_fail "could not parse hooks[].hooks[].command entries in .claude/settings.json (malformed hook entry?)"
  fi
else
  check_fail ".claude/settings.json missing or invalid JSON — cannot derive hook set"
fi

if [ "$HOOK_FILES_OK" -eq 1 ] && [ -z "$HOOK_FILES" ]; then
  check_fail "no hooks registered in .claude/settings.json"
elif [ "$HOOK_FILES_OK" -eq 1 ]; then
  for f in $HOOK_FILES; do
    p=".claude/hooks/${f}"
    if [ -x "$p" ]; then
      check_ok "$p present and executable (registered)"
    else
      check_fail "$p registered in settings.json but missing or not executable"
    fi
  done
fi

echo ""
echo "== Event bindings (per hook) =="
# For each derived hook, report which lifecycle event(s) it is bound to, then
# assert the known load-bearing gates land in their expected event. A hook
# bound to zero events (present in HOOK_FILES but not matched by any event's
# .hooks[].command) is reported, not silently passed.
if [ "$HOOK_FILES_OK" -eq 1 ] && [ -n "$HOOK_FILES" ]; then
  for f in $HOOK_FILES; do
    # Match on the command's exact basename, not a raw substring: e.g.
    # "database-sentinel.sh" is a substring of "legacy-database-sentinel.sh"
    # and a plain `contains($f)` would falsely report the former as bound to
    # whatever event the latter is on. Mirrors the exact-match derivation
    # used above (line ~45) and the dead-hook check below (line ~143).
    ev=$(jq -r --arg f "$f" '
      [.hooks // {} | to_entries[]
        | .key as $event
        | .value[]?
        | .hooks[]?
        | select(.command? and (.command | type == "string"))
        | select((.command | capture("(?<b>[A-Za-z0-9._-]+\\.(sh|cjs))")? | .b) == $f)
        | $event]
      | unique | join(",")
    ' .claude/settings.json 2>/dev/null) || ev=""

    if [ -n "$ev" ]; then
      check_ok "$f registered in: $ev"
    else
      check_fail "$f registered in settings.json but bound to zero events (unreachable hook)"
    fi

    # Known load-bearing gates the pre-rewrite script (90b807b) verified by
    # name — restored here as an expected-EVENT map, not a hardcoded
    # existence list: a hook absent from HOOK_FILES is simply not iterated
    # over, this only asserts correct wiring for gates that *are* present.
    # phase-sentinel: migration 0022 repointed it from a prompt-type Stop
    # hook to a deterministic type:command Stop hook, so we assert Stop
    # (its current, correct binding) rather than resurrecting the now-stale
    # prompt-type check.
    base="${f%.sh}"; base="${base%.cjs}"
    expected=""
    case "$base" in
      database-sentinel)      expected="PreToolUse" ;;
      design-shotgun-gate)    expected="PreToolUse" ;;
      multi-ai-review-gate)   expected="PreToolUse" ;;
      skill-router-log)       expected="PostToolUse" ;;
      session-bootstrap)      expected="SessionStart" ;;
      phase-sentinel)         expected="Stop" ;;
    esac
    if [ -n "$expected" ]; then
      if printf '%s' "$ev" | tr ',' '\n' | grep -qxF "$expected"; then
        check_ok "$f (load-bearing gate) correctly bound to $expected"
      else
        check_fail "$f (load-bearing gate) NOT bound to expected event $expected (found: ${ev:-none}) — gate may be defeated"
      fi
    fi
  done
fi

echo ""
echo "== Global (~/.claude/hooks/) =="
if [ -x "$HOME/.claude/hooks/commitment-reinject.sh" ]; then
  check_ok "commitment-reinject.sh present and executable"
else
  check_fail "commitment-reinject.sh missing or not executable"
fi

echo ""
echo "== Project settings (.claude/settings.json) =="
if [ -f .claude/settings.json ] && jq empty .claude/settings.json 2>/dev/null; then
  # Every hook file on disk should be registered (the reverse direction).
  # Match against the DERIVED set with exact basename equality, not a raw
  # substring grep on settings.json's text — an on-disk "gate.sh" is a
  # substring of the registered "multi-ai-review-gate.sh" and would falsely
  # read as registered under a plain `grep -F`, hiding a genuinely dead hook.
  if [ "$HOOK_FILES_OK" -eq 1 ]; then
    for p in .claude/hooks/*.sh .claude/hooks/*.cjs; do
      [ -e "$p" ] || continue
      b=$(basename "$p")
      if printf '%s\n' "$HOOK_FILES" | grep -qxF "$b"; then
        check_ok "$b registered in settings.json"
      else
        check_fail "$b present on disk but NOT registered in settings.json (dead hook)"
      fi
    done
  else
    check_fail "cannot check for dead hooks — hook set derivation failed above"
  fi
  # The plan-review gate is load-bearing (spec §02 plan-review, ADR-0025).
  if [ "$HOOK_FILES_OK" -eq 1 ] && printf '%s\n' "$HOOK_FILES" | grep -qxF "multi-ai-review-gate.sh"; then
    check_ok "plan-review gate (multi-ai-review-gate) registered"
  else
    check_fail "plan-review gate (multi-ai-review-gate) NOT registered — spec §02 gate unbound"
  fi
else
  check_fail ".claude/settings.json missing or invalid JSON"
fi

echo ""
echo "== Global settings (~/.claude/settings.json) =="
if [ -f "$HOME/.claude/settings.json" ] && jq empty "$HOME/.claude/settings.json" 2>/dev/null; then
  if jq -e '.hooks.SessionStart[]? | select(.matcher == "compact" and (.hooks[].command | contains("commitment-reinject")))' "$HOME/.claude/settings.json" >/dev/null; then
    check_ok "Hook 5 (Commitment Re-Injector) registered globally with matcher: compact"
  else
    check_fail "Hook 5 (Commitment Re-Injector) NOT registered globally"
  fi
else
  check_fail "~/.claude/settings.json missing or invalid JSON"
fi

echo ""
echo "Result: ${OK} ok, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
