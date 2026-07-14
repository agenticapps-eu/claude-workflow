#!/usr/bin/env bash
# check-hooks.sh — verify every programmatic hook registered in the project's
# .claude/settings.json is present and executable (and vice versa), plus the
# global commitment-reinject hook. The expected set is DERIVED from
# settings.json, never hardcoded — see ADR-0040.
#
# Usage: cd <agenticapps-project> && /path/to/scaffolder/bin/check-hooks.sh
# Exit 0 if all OK; exit 1 if anything missing/misregistered.

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
if [ -f .claude/settings.json ] && jq empty .claude/settings.json 2>/dev/null; then
  HOOK_FILES=$(jq -r '
    [.hooks // {} | .[]? | .[]? | .hooks[]? | select(.command?) | .command]
    | map(capture("(?<f>[A-Za-z0-9._-]+\\.(sh|cjs))").f) | unique | .[]
  ' .claude/settings.json)
else
  HOOK_FILES=""
  check_fail ".claude/settings.json missing or invalid JSON — cannot derive hook set"
fi

if [ -z "$HOOK_FILES" ]; then
  check_fail "no hooks registered in .claude/settings.json"
else
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
  for p in .claude/hooks/*.sh .claude/hooks/*.cjs; do
    [ -e "$p" ] || continue
    b=$(basename "$p")
    if grep -qF "$b" .claude/settings.json; then
      check_ok "$b registered in settings.json"
    else
      check_fail "$b present on disk but NOT registered in settings.json (dead hook)"
    fi
  done
  # The plan-review gate is load-bearing (spec §02 plan-review, ADR-0025).
  if grep -qF "multi-ai-review-gate" .claude/settings.json; then
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
