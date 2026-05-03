#!/usr/bin/env bash
# architecture-audit-check.sh — SessionStart reminder for stale architecture audits.
#
# Fires on SessionStart in any AgenticApps project. Checks the date of
# the last architecture audit; if >7 days, prompts the user to run
# /improve-codebase-architecture. Honors per-project snooze markers.
# Non-blocking — informational only (always exit 0).
#
# Pairs with the weekly LaunchAgent / systemd-user cron at
# bin/agenticapps-architecture-cron.sh for out-of-session reminders.
#
# Source: synthesis report §1 + handoff prompt Phase 4 Mechanism 1.

set -e

# Step 1: detect AgenticApps project
[ -d .planning ] || exit 0
test -f .claude/skills/agentic-apps-workflow/SKILL.md \
  || test -f "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" \
  || test -L "$HOME/.claude/skills/agentic-apps-workflow" \
  || exit 0

# Step 2: honor snooze
SNOOZE_DIR=.planning/audits
TODAY=$(date +%Y-%m-%d)
if [ -d "$SNOOZE_DIR" ]; then
  for snooze in "$SNOOZE_DIR"/.snooze-until-*; do
    [ -e "$snooze" ] || continue
    SNOOZE_DATE="${snooze##*.snooze-until-}"
    if [[ "$SNOOZE_DATE" > "$TODAY" ]]; then
      exit 0
    fi
  done
fi

# Step 3: check last audit date
AUDIT_DIR=.planning/audits
LATEST=""
[ -d "$AUDIT_DIR" ] && LATEST=$(ls -t "$AUDIT_DIR"/*-architecture.md 2>/dev/null | head -1)

NOW=$(date +%s)
THRESHOLD=7
if [ -z "$LATEST" ]; then
  STATUS="never"
else
  AUDIT_DATE=$(stat -f %m "$LATEST" 2>/dev/null || stat -c %Y "$LATEST" 2>/dev/null)
  DAYS=$(( (NOW - AUDIT_DATE) / 86400 ))
  if [ "$DAYS" -le "$THRESHOLD" ]; then
    exit 0   # in date — silent
  fi
  STATUS="$DAYS days"
fi

# Step 4: prompt
SNOOZE_DATE=$(date -v+7d +%Y-%m-%d 2>/dev/null || date -d '+7 days' +%Y-%m-%d 2>/dev/null || echo "next-week")
echo ""
echo "## 🏗  Architecture audit check"
echo ""
if [ "$STATUS" = "never" ]; then
  echo "This project has never had an architecture audit."
else
  echo "This project's last architecture audit was $STATUS ago (threshold: ${THRESHOLD} days)."
fi
echo ""
echo "Consider running: /improve-codebase-architecture"
echo "  Output: .planning/audits/$(date +%Y-%m-%d)-architecture.md"
echo ""
echo "Snooze for 7 days:"
echo "  mkdir -p .planning/audits && touch .planning/audits/.snooze-until-${SNOOZE_DATE}"
echo ""

exit 0
