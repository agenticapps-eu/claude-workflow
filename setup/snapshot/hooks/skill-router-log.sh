#!/usr/bin/env bash
# Hook 4a — Skill Router Audit Log (PostToolUse)
#
# Records every skill invocation as a JSONL line for observability.
# Logs go to .planning/skill-observations/skill-router-{date}.jsonl per
# Q6 design choice (same dir as agenticapps-meta-observer outputs;
# distinct filename schema; dashboard merges by timestamp).
#
# Fires on PostToolUse matcher: mcp__skills__.*|Bash
# Always returns exit 0 (logging is informational, never blocks).
#
# Source: synthesis report §3 Hook 4a + handoff prompt Phase 2E.

set -e

# Be cwd-aware — non-AgenticApps projects don't have .planning.
[ -d .planning ] || exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Detect skill name.
SKILL=""
case "$TOOL" in
  mcp__skills__*)
    # Skill MCP tool — extract from tool name or input.
    SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
    if [ -z "$SKILL" ]; then
      # Fallback: parse from tool_name (e.g. mcp__skills__brainstorming → brainstorming)
      SKILL=$(echo "$TOOL" | sed 's/^mcp__skills__//')
    fi
    ;;
  Bash)
    # Look for skill invocation patterns in the command.
    if echo "$COMMAND" | grep -qE '(^|[[:space:]])Skill[[:space:]]+[a-zA-Z0-9_:-]+'; then
      SKILL=$(echo "$COMMAND" | grep -oE 'Skill[[:space:]]+[a-zA-Z0-9_:-]+' | head -1 | awk '{print $2}')
    fi
    ;;
esac

[ -n "$SKILL" ] || exit 0

# Identify current phase.
PHASE="unknown"
if [ -d .planning/phases ]; then
  PHASE_DIR=$(find .planning/phases -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)
  if [ -n "$PHASE_DIR" ]; then
    PHASE=$(basename "$PHASE_DIR")
  fi
fi

# Append JSONL line. Filename schema per Q6: skill-router-{date}.jsonl.
DATE=$(date -u +%Y-%m-%d)
LOG_DIR=.planning/skill-observations
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/skill-router-${DATE}.jsonl"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# Use jq to safely encode in case skill/phase contain special chars.
jq -nc --arg ts "$TS" --arg skill "$SKILL" --arg phase "$PHASE" --arg tool "$TOOL" \
  '{ts: $ts, skill: $skill, phase: $phase, tool: $tool}' >> "$LOG_FILE"

exit 0
