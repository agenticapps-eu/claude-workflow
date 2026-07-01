#!/usr/bin/env bash
# Hook 4b — Session Bootstrap (SessionStart)
#
# Surfaces the most recent skill invocations from the audit log when a
# new session starts. Pairs with skill-router-log.sh (Hook 4a) — that
# hook writes the log; this one reads it back to warm context.
#
# Fires on SessionStart (no matcher; runs on every session start).
# Always returns exit 0.
#
# Source: synthesis report §3 Hook 4b + handoff prompt Phase 2E.

set -e

# Be cwd-aware — non-AgenticApps projects don't have .planning.
[ -d .planning ] || exit 0

LOG_DIR=.planning/skill-observations
[ -d "$LOG_DIR" ] || exit 0

# Find the most recent skill-router log file.
LATEST=$(ls -t "$LOG_DIR"/skill-router-*.jsonl 2>/dev/null | head -1)
[ -n "$LATEST" ] || exit 0

echo "## Recent skill invocations (from $(basename "$LATEST"))"
echo ""
tail -20 "$LATEST"

exit 0
