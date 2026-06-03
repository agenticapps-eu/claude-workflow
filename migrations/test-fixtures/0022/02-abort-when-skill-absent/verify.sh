#!/bin/sh
# Verify the migration's pre-flight #1 abort path (obs skill absent). This script
# REPLAYS the migration's pre-flight #1 block verbatim and asserts it exits 3
# with the actionable install pointer (no auto-install, D-03).
# NOTE: `set -e` is intentionally NOT used here — we capture the abort exit code.
set -u

# Confirm the precondition the fixture establishes: obs skill is absent.
if [ -f "$HOME/.claude/skills/observability/SKILL.md" ]; then
  echo "fixture 02 expects obs skill ABSENT but it is present"
  exit 1
fi

# Replay the migration's pre-flight #1 (verbatim shape from 0022).
out=$(
  test -f "$HOME/.claude/skills/observability/SKILL.md" || {
    echo "ABORT: The 'observability' skill is not installed."
    echo "Install agenticapps-observability separately:"
    echo ""
    echo "  git clone https://github.com/agenticapps-eu/agenticapps-observability \\"
    echo "    ~/.claude/skills/agenticapps-observability"
    echo "  bash ~/.claude/skills/agenticapps-observability/install.sh"
    echo ""
    echo "Then re-run /update-agenticapps-workflow."
    exit 3
  }
)
rc=$?

if [ "$rc" != "3" ]; then
  echo "pre-flight should abort with exit 3 when obs skill absent, got $rc"
  exit 1
fi

# Assert the actionable pointer is present (no auto-install message).
printf '%s\n' "$out" | grep -q "ABORT: The 'observability' skill is not installed" \
  || { echo "abort message missing the actionable pointer"; exit 1; }
printf '%s\n' "$out" | grep -q "agenticapps-observability" \
  || { echo "abort message should point at agenticapps-observability install"; exit 1; }

echo "fixture 02 — pre-flight aborts (exit 3) with install pointer; no auto-install"
exit 0
