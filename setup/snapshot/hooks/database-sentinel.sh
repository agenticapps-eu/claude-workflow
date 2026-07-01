#!/usr/bin/env bash
# Hook 1 — Database Sentinel (PreToolUse)
#
# Blocks dangerous DB operations and edits to protected files at the
# tool-call boundary. Promotes the AgenticApps "database-sentinel" gate
# from CLAUDE.md prose intent to non-overridable enforcement.
#
# Fires on PreToolUse matcher: Bash|Edit|Write
# Reads tool_input from stdin (JSON).
# Exit 2 = BLOCK (with stderr message routed to Claude as feedback).
# Exit 0 = ALLOW.
#
# Latency budget: sub-100ms. Regex only; no DB calls, no network.
#
# Source: synthesis report §3 Hook 1 + handoff prompt Phase 2B.

set -e

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Bash tool — block dangerous SQL.
if [ "$TOOL" = "Bash" ]; then
  # DROP TABLE, TRUNCATE TABLE, DELETE FROM <table> without WHERE.
  # Case-insensitive. Allow DELETE FROM ... WHERE ... (legitimate use).
  if echo "$COMMAND" | grep -qiE 'drop[[:space:]]+table|truncate[[:space:]]+table'; then
    echo "❌ Database Sentinel: blocked dangerous SQL DDL" >&2
    echo "   Command: $COMMAND" >&2
    echo "   Reason: matches DROP/TRUNCATE TABLE pattern" >&2
    echo "   Override: run via psql directly outside Claude Code, OR" >&2
    echo "             reference an ADR that accepts the destructive operation" >&2
    exit 2
  fi
  if echo "$COMMAND" | grep -qiE 'delete[[:space:]]+from[[:space:]]+[a-z_][a-z0-9_]*[[:space:]]*(;|$)'; then
    echo "❌ Database Sentinel: blocked DELETE without WHERE clause" >&2
    echo "   Command: $COMMAND" >&2
    echo "   Reason: deletes all rows. Add a WHERE clause or run outside Claude Code." >&2
    exit 2
  fi
fi

# Edit/Write — protect sensitive paths.
if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ]; then
  case "$FILE" in
    .env|.env.local|.env.production|.env.staging|.env.development|*/.env|*/.env.local|*/.env.production|*/.env.staging|*/.env.development)
      echo "❌ Database Sentinel: blocked edit to env file" >&2
      echo "   File: $FILE" >&2
      echo "   Reason: env files contain secrets — use Infisical or similar" >&2
      echo "   Allowed: .env.example, .env.template" >&2
      exit 2
      ;;
    migrations/*|*/migrations/*)
      # Only allow migration edits when the phase has been approved.
      if [ ! -f .planning/current-phase/migrations-approved ]; then
        echo "❌ Database Sentinel: blocked edit to migration without phase approval" >&2
        echo "   File: $FILE" >&2
        echo "   Reason: no .planning/current-phase/migrations-approved sentinel" >&2
        echo "   Fix: in /gsd-discuss-phase, mark migration scope approved:" >&2
        echo "        touch .planning/current-phase/migrations-approved" >&2
        exit 2
      fi
      ;;
  esac
fi

exit 0
