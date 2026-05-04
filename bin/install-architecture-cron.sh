#!/usr/bin/env bash
# install-architecture-cron.sh — register the weekly AgenticApps
# architecture audit reminder as a macOS LaunchAgent.
#
# Idempotent: re-running unloads any existing agent and re-loads it.
# Linux equivalent: bin/install-systemd-architecture-cron.sh

set -euo pipefail

if [[ "$OSTYPE" != darwin* ]]; then
  echo "ERROR: this installer is macOS only."
  echo "On Linux, use: bin/install-systemd-architecture-cron.sh"
  exit 1
fi

SCAFFOLDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLDER_BIN="$SCAFFOLDER_DIR/bin"
TEMPLATE="$SCAFFOLDER_DIR/templates/launchd/eu.agenticapps.architecture-cron.plist"
PLIST="$HOME/Library/LaunchAgents/eu.agenticapps.architecture-cron.plist"

[ -f "$TEMPLATE" ] || { echo "ERROR: template not found at $TEMPLATE"; exit 1; }
[ -x "$SCAFFOLDER_BIN/agenticapps-architecture-cron.sh" ] || {
  echo "ERROR: cron script not executable at $SCAFFOLDER_BIN/agenticapps-architecture-cron.sh"
  exit 1
}

mkdir -p "$HOME/.agenticapps/logs"
mkdir -p "$HOME/Library/LaunchAgents"

# Substitute paths into the template.
sed -e "s|{SCAFFOLDER_BIN}|$SCAFFOLDER_BIN|g" \
    -e "s|{HOME}|$HOME|g" \
    "$TEMPLATE" > "$PLIST"

# Idempotent: unload then load.
launchctl unload -w "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

echo "✅ Architecture audit cron installed (LaunchAgent)"
echo "   Schedule: Mondays at 09:00 local"
echo "   Plist:    $PLIST"
echo "   Logs:     ~/.agenticapps/logs/architecture-cron-{stdout,stderr}.log"
echo ""
echo "Verify: launchctl list | grep agenticapps"
echo "Run now: launchctl start eu.agenticapps.architecture-cron"
echo "Uninstall: launchctl unload -w $PLIST && rm $PLIST"
