#!/usr/bin/env bats
# Tests for skill-router-log.sh (Hook 4a, PostToolUse) +
# session-bootstrap.sh (Hook 4b, SessionStart).
# Spec: synthesis report §3 Hook 4 + handoff prompt Phase 2E.

LOG_HOOK="$BATS_TEST_DIRNAME/../../templates/.claude/hooks/skill-router-log.sh"
BOOTSTRAP_HOOK="$BATS_TEST_DIRNAME/../../templates/.claude/hooks/session-bootstrap.sh"

setup() {
  TMPDIR=$(mktemp -d -t skill-router-test-XXXXXX)
  cd "$TMPDIR"
}

teardown() {
  cd /
  rm -rf "$TMPDIR"
}

mk_skill_input() {
  jq -nc --arg tool "$1" --arg skill "$2" \
    '{tool_name: $tool, tool_input: ($skill | if . != "" then {skill: .} else {} end)}'
}

mk_bash_input() {
  jq -nc --arg cmd "$1" '{tool_name: "Bash", tool_input: {command: $cmd}}'
}

# === skill-router-log.sh (4a) ===

@test "no .planning → exit 0, no log written" {
  run bash -c "echo '$(mk_skill_input "mcp__skills__brainstorming" "brainstorming")' | $LOG_HOOK"
  [ "$status" -eq 0 ]
  [ ! -d .planning/skill-observations ]
}

@test "mcp__skills__ tool fires → JSONL line appended" {
  mkdir -p .planning
  run bash -c "echo '$(mk_skill_input "mcp__skills__brainstorming" "brainstorming")' | $LOG_HOOK"
  [ "$status" -eq 0 ]
  LATEST=$(ls .planning/skill-observations/skill-router-*.jsonl)
  [ -n "$LATEST" ]
  jq -e '.skill == "brainstorming" and .tool == "mcp__skills__brainstorming"' "$LATEST"
}

@test "mcp__skills__ tool — skill name fallback from tool_name" {
  mkdir -p .planning
  # tool_input has no .skill field; expect parse from tool_name
  INPUT=$(jq -nc '{tool_name: "mcp__skills__foo", tool_input: {}}')
  run bash -c "echo '$INPUT' | $LOG_HOOK"
  [ "$status" -eq 0 ]
  LATEST=$(ls .planning/skill-observations/skill-router-*.jsonl)
  jq -e '.skill == "foo"' "$LATEST"
}

@test "Bash tool with 'Skill X' substring → JSONL line appended" {
  mkdir -p .planning
  run bash -c "echo '$(mk_bash_input "Skill brainstorming run me")' | $LOG_HOOK"
  [ "$status" -eq 0 ]
  LATEST=$(ls .planning/skill-observations/skill-router-*.jsonl 2>/dev/null)
  [ -n "$LATEST" ]
  jq -e '.skill == "brainstorming"' "$LATEST"
}

@test "Bash tool with non-Skill command → no log" {
  mkdir -p .planning
  run bash -c "echo '$(mk_bash_input "ls -la")' | $LOG_HOOK"
  [ "$status" -eq 0 ]
  [ -z "$(ls .planning/skill-observations/ 2>/dev/null)" ]
}

@test "phase derived from highest-numbered phase dir" {
  mkdir -p .planning/phases/01-old .planning/phases/02-current
  run bash -c "echo '$(mk_skill_input "mcp__skills__brainstorming" "brainstorming")' | $LOG_HOOK"
  [ "$status" -eq 0 ]
  LATEST=$(ls .planning/skill-observations/skill-router-*.jsonl)
  jq -e '.phase == "02-current"' "$LATEST"
}

@test "phase=unknown when no phases/ subdir exists" {
  mkdir -p .planning
  run bash -c "echo '$(mk_skill_input "mcp__skills__foo" "foo")' | $LOG_HOOK"
  [ "$status" -eq 0 ]
  LATEST=$(ls .planning/skill-observations/skill-router-*.jsonl)
  jq -e '.phase == "unknown"' "$LATEST"
}

# === session-bootstrap.sh (4b) ===

@test "session-bootstrap: no .planning → exit 0, no output" {
  run "$BOOTSTRAP_HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-bootstrap: .planning but no skill-observations → exit 0, no output" {
  mkdir -p .planning
  run "$BOOTSTRAP_HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-bootstrap: log file present → outputs last 20 lines" {
  mkdir -p .planning/skill-observations
  for i in {1..30}; do
    echo "{\"ts\":\"2026-05-03T00:00:${i}Z\",\"skill\":\"skill-${i}\"}" >> .planning/skill-observations/skill-router-2026-05-03.jsonl
  done
  run "$BOOTSTRAP_HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recent skill invocations"* ]]
  [[ "$output" == *"skill-30"* ]]   # last line included
  [[ "$output" == *"skill-11"* ]]   # 20 from end
  [[ "$output" != *"\"skill\":\"skill-1\""* ]]    # exact: skill-1 not in tail-20 (skill-10 is though)
}

@test "session-bootstrap: latency under 100ms" {
  mkdir -p .planning/skill-observations
  for i in {1..50}; do
    echo "{\"ts\":\"2026-05-03T00:00:${i}Z\",\"skill\":\"s${i}\"}" >> .planning/skill-observations/skill-router-2026-05-03.jsonl
  done
  start=$(gdate +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  "$BOOTSTRAP_HOOK" >/dev/null
  end=$(gdate +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  elapsed_ms=$(( (end - start) / 1000000 ))
  echo "elapsed: ${elapsed_ms}ms"
  [ "$elapsed_ms" -lt 100 ]
}
