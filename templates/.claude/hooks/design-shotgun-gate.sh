#!/usr/bin/env bash
# Hook 2 — Design Shotgun Pre-Flight Gate (PreToolUse)
#
# Blocks edits to design surfaces unless the design-preflight sentinel
# is present. Composes with the agenticapps-design-preflight skill (when
# shipped): the skill writes the sentinel on successful pre-flight; this
# hook enforces its presence.
#
# Fires on PreToolUse matcher: Edit|Write
# Exit 2 = BLOCK; Exit 0 = ALLOW.
# Latency budget: sub-100ms.
#
# Source: synthesis report §3 Hook 2 + handoff prompt Phase 2C.

set -e

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only Edit/Write are subject to this gate.
[ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || exit 0
[ -n "$FILE" ] || exit 0

# Match design-surface paths.
case "$FILE" in
  *.tsx|*.css|*.scss|*.module.css|*.module.scss|design/*|*/design/*|src/components/*|*/src/components/*|src/styles/*|*/src/styles/*)
    if [ ! -f .planning/current-phase/design-shotgun-passed ]; then
      echo "❌ Design Shotgun Gate: blocked edit to design surface" >&2
      echo "   File: $FILE" >&2
      echo "   Reason: no .planning/current-phase/design-shotgun-passed sentinel" >&2
      echo "   Fix: run /design-shotgun and let preflight write the sentinel," >&2
      echo "        OR for an intentional one-off:" >&2
      echo "        touch .planning/current-phase/design-shotgun-passed" >&2
      echo "        (and document the override in the commit message)" >&2
      exit 2
    fi
    ;;
esac

exit 0
