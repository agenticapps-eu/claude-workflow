#!/usr/bin/env bash
# check-hooks.sh — verify all 5 programmatic hooks are installed correctly
# in the current project (project-scoped Hooks 1-4 + global Hook 5).
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
for h in database-sentinel design-shotgun-gate skill-router-log session-bootstrap; do
  f=".claude/hooks/${h}.sh"
  if [ -x "$f" ]; then
    check_ok "$f present and executable"
  else
    check_fail "$f missing or not executable"
  fi
done

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
  if jq -e '.hooks.PreToolUse[]? | select(.hooks[].command | contains("database-sentinel"))' .claude/settings.json >/dev/null; then
    check_ok "Hook 1 (Database Sentinel) registered in PreToolUse"
  else
    check_fail "Hook 1 (Database Sentinel) NOT registered in PreToolUse"
  fi
  if jq -e '.hooks.PreToolUse[]? | select(.hooks[].command | contains("design-shotgun-gate"))' .claude/settings.json >/dev/null; then
    check_ok "Hook 2 (Design Shotgun Gate) registered in PreToolUse"
  else
    check_fail "Hook 2 (Design Shotgun Gate) NOT registered in PreToolUse"
  fi
  if jq -e '.hooks.Stop[]? | select(.hooks[].type == "prompt")' .claude/settings.json >/dev/null; then
    check_ok "Hook 3 (Phase Sentinel) registered in Stop (prompt-type)"
  else
    check_fail "Hook 3 (Phase Sentinel) NOT registered in Stop"
  fi
  if jq -e '.hooks.PostToolUse[]? | select(.hooks[].command | contains("skill-router-log"))' .claude/settings.json >/dev/null; then
    check_ok "Hook 4a (Skill Router Log) registered in PostToolUse"
  else
    check_fail "Hook 4a (Skill Router Log) NOT registered in PostToolUse"
  fi
  if jq -e '.hooks.SessionStart[]? | select(.hooks[].command | contains("session-bootstrap"))' .claude/settings.json >/dev/null; then
    check_ok "Hook 4b (Session Bootstrap) registered in SessionStart"
  else
    check_fail "Hook 4b (Session Bootstrap) NOT registered in SessionStart"
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
