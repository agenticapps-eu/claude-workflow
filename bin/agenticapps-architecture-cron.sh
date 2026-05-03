#!/usr/bin/env bash
# Weekly architecture audit cron — scans active AgenticApps projects
# and creates Linear issues (or local log) for those with overdue
# audits. Designed to be invoked by:
#  - macOS LaunchAgent (Mondays 09:00 local) — see templates/launchd/
#  - Linux systemd-user .timer (same schedule) — see templates/systemd-user/
#
# Source-of-truth for "active projects": ~/.agenticapps/dashboard/registry.json
# (preferred per Q2). Falls back to scanning ~/Sourcecode for repos with
# .planning/ if the registry is empty or absent (also per Q2's "robust"
# option C semantics — registry-first, fallback heuristic).

set -euo pipefail

REGISTRY="${AGENTICAPPS_REGISTRY:-$HOME/.agenticapps/dashboard/registry.json}"
THRESHOLD_DAYS="${ARCHITECTURE_AUDIT_THRESHOLD_DAYS:-7}"
SOURCECODE_ROOT="${AGENTICAPPS_SOURCECODE_ROOT:-$HOME/Sourcecode}"
LOG_FILE="${HOME}/.agenticapps/architecture-audit-cron.log"

mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$LOG_FILE"; }

PROJECTS=()

# Source 1: registry (preferred).
if [ -f "$REGISTRY" ]; then
  REGISTRY_PROJECTS=$(jq -r '
    .projects // [] |
    map(select(.tags // [] | index("active"))) |
    .[] | .root
  ' "$REGISTRY" 2>/dev/null || true)
  if [ -n "$REGISTRY_PROJECTS" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] && PROJECTS+=("$p")
    done <<< "$REGISTRY_PROJECTS"
  fi
fi

# Source 2: heuristic fallback (only if registry empty or absent).
if [ "${#PROJECTS[@]}" -eq 0 ]; then
  log "registry empty/absent; falling back to heuristic scan of $SOURCECODE_ROOT"
  if [ -d "$SOURCECODE_ROOT" ]; then
    while IFS= read -r dir; do
      [ -d "$dir/.planning" ] && PROJECTS+=("$dir")
    done < <(find "$SOURCECODE_ROOT" -maxdepth 3 -type d -name '.planning' -prune 2>/dev/null | xargs -n1 dirname 2>/dev/null)
  fi
fi

if [ "${#PROJECTS[@]}" -eq 0 ]; then
  log "no AgenticApps projects found in registry or fallback scan; nothing to do"
  echo "No AgenticApps projects detected."
  exit 0
fi

NOW=$(date +%s)
TODAY=$(date +%Y-%m-%d)
OVERDUE=()

for PROJECT in "${PROJECTS[@]}"; do
  AUDIT_DIR="$PROJECT/.planning/audits"

  # Honor snooze (per Q2 robust semantics: same snooze marker as the SessionStart skill).
  SNOOZED=0
  if [ -d "$AUDIT_DIR" ]; then
    for snooze in "$AUDIT_DIR"/.snooze-until-*; do
      [ -e "$snooze" ] || continue
      SNOOZE_DATE="${snooze##*.snooze-until-}"
      if [[ "$SNOOZE_DATE" > "$TODAY" ]]; then
        SNOOZED=1
        break
      fi
    done
  fi
  [ "$SNOOZED" = "1" ] && continue

  LATEST=""
  if [ -d "$AUDIT_DIR" ]; then
    LATEST=$(ls -t "$AUDIT_DIR"/*-architecture.md 2>/dev/null | head -1)
  fi

  if [ -z "$LATEST" ]; then
    OVERDUE+=("$PROJECT (never audited)")
  else
    AUDIT_DATE=$(stat -f %m "$LATEST" 2>/dev/null || stat -c %Y "$LATEST" 2>/dev/null)
    DAYS=$(( (NOW - AUDIT_DATE) / 86400 ))
    if [ "$DAYS" -gt "$THRESHOLD_DAYS" ]; then
      OVERDUE+=("$PROJECT ($DAYS days)")
    fi
  fi
done

if [ "${#OVERDUE[@]}" -eq 0 ]; then
  log "all ${#PROJECTS[@]} active projects audited within $THRESHOLD_DAYS days"
  echo "✓ All ${#PROJECTS[@]} active projects audited within $THRESHOLD_DAYS days. Nothing to do."
  exit 0
fi

log "OVERDUE: ${OVERDUE[*]}"
echo "Overdue projects:"
printf '  - %s\n' "${OVERDUE[@]}"

# Linear notification (best-effort; multiple paths tried).
ISSUE_TITLE="Weekly architecture audit reminder ($TODAY)"
ISSUE_BODY=$(printf '## Overdue projects (threshold: %d days)\n\n' "$THRESHOLD_DAYS")
for P in "${OVERDUE[@]}"; do
  ISSUE_BODY+=$(printf '\n- %s' "$P")
done
ISSUE_BODY+=$'\n\nRun `/improve-codebase-architecture` in each project (after CONTEXT.md and `mattpocock-improve-architecture` skill are present).\n\nSnooze for 7 days per project: `mkdir -p .planning/audits && touch .planning/audits/.snooze-until-$(date -v+7d +%Y-%m-%d)`'

NOTIFIED=0
if command -v linear >/dev/null 2>&1; then
  if linear issue create --title "$ISSUE_TITLE" --body "$ISSUE_BODY" >/dev/null 2>&1; then
    log "filed Linear issue via linear CLI"
    NOTIFIED=1
  fi
fi

if [ "$NOTIFIED" = "0" ]; then
  log "no Linear access; logging only"
  {
    echo "  TITLE: $ISSUE_TITLE"
    echo "  BODY:"
    echo "$ISSUE_BODY" | sed 's/^/    /'
  } >> "$LOG_FILE"
  echo "  → Logged to $LOG_FILE (no Linear CLI available)"
fi

exit 0
