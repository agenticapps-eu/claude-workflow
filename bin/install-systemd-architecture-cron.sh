#!/usr/bin/env bash
# install-systemd-architecture-cron.sh — register the weekly
# AgenticApps architecture audit reminder as a systemd-user .timer.
#
# Idempotent: re-running disables/stops then re-enables/starts.
# macOS equivalent: bin/install-architecture-cron.sh

set -euo pipefail

if [[ "$OSTYPE" == darwin* ]]; then
  echo "ERROR: this installer is Linux (systemd) only."
  echo "On macOS, use: bin/install-architecture-cron.sh"
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "ERROR: systemctl not found. This installer requires systemd."
  exit 1
fi

SCAFFOLDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLDER_BIN="$SCAFFOLDER_DIR/bin"
TEMPLATES="$SCAFFOLDER_DIR/templates/systemd-user"
TARGET_DIR="$HOME/.config/systemd/user"

mkdir -p "$TARGET_DIR" "$HOME/.agenticapps/logs"

# Substitute paths and copy.
for unit in agenticapps-architecture-cron.service agenticapps-architecture-cron.timer; do
  sed -e "s|{SCAFFOLDER_BIN}|$SCAFFOLDER_BIN|g" \
      -e "s|{HOME}|$HOME|g" \
      "$TEMPLATES/$unit" > "$TARGET_DIR/$unit"
done

# Idempotent: stop + disable + reload + enable + start.
systemctl --user stop agenticapps-architecture-cron.timer 2>/dev/null || true
systemctl --user disable agenticapps-architecture-cron.timer 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable --now agenticapps-architecture-cron.timer

echo "✅ Architecture audit cron installed (systemd-user)"
echo "   Schedule: Mondays at 09:00 local"
echo "   Units:    $TARGET_DIR/agenticapps-architecture-cron.{service,timer}"
echo "   Logs:     ~/.agenticapps/logs/architecture-cron-{stdout,stderr}.log"
echo ""
echo "Verify: systemctl --user list-timers | grep agenticapps"
echo "Run now: systemctl --user start agenticapps-architecture-cron.service"
echo "Uninstall: systemctl --user disable --now agenticapps-architecture-cron.timer"
