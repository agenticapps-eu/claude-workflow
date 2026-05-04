#!/usr/bin/env bats
# Tests for design-shotgun-gate.sh (Hook 2, PreToolUse)
# Spec: synthesis report §3 Hook 2 + handoff prompt Phase 2C.

HOOK="$BATS_TEST_DIRNAME/../../templates/.claude/hooks/design-shotgun-gate.sh"

setup() {
  TMPDIR=$(mktemp -d -t design-gate-test-XXXXXX)
  cd "$TMPDIR"
}

teardown() {
  cd /
  rm -rf "$TMPDIR"
}

mk_input() {
  jq -nc --arg tool "$1" --arg path "$2" '{tool_name: $tool, tool_input: {file_path: $path}}'
}

@test "Edit src/components/Button.tsx without sentinel → blocked (exit 2)" {
  run bash -c "echo '$(mk_input "Edit" "src/components/Button.tsx")' | $HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"design-shotgun-passed"* ]]
}

@test "Edit src/components/Button.tsx WITH sentinel → allowed (exit 0)" {
  mkdir -p .planning/current-phase
  touch .planning/current-phase/design-shotgun-passed
  run bash -c "echo '$(mk_input "Edit" "src/components/Button.tsx")' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "Edit src/lib/util.ts (non-design) → allowed (exit 0)" {
  run bash -c "echo '$(mk_input "Edit" "src/lib/util.ts")' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "Edit README.md → allowed (exit 0)" {
  run bash -c "echo '$(mk_input "Edit" "README.md")' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "Write design/preview.tsx without sentinel → blocked (exit 2)" {
  run bash -c "echo '$(mk_input "Write" "design/preview.tsx")' | $HOOK"
  [ "$status" -eq 2 ]
}

@test "Edit src/styles/main.css without sentinel → blocked (exit 2)" {
  run bash -c "echo '$(mk_input "Edit" "src/styles/main.css")' | $HOOK"
  [ "$status" -eq 2 ]
}

@test "Edit foo.module.scss without sentinel → blocked (exit 2)" {
  run bash -c "echo '$(mk_input "Edit" "foo.module.scss")' | $HOOK"
  [ "$status" -eq 2 ]
}

@test "Bash tool (out of matcher) → allowed (exit 0)" {
  run bash -c "echo '$(jq -nc "{tool_name: \"Bash\", tool_input: {command: \"ls\"}}")' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "latency: under 100ms" {
  INPUT=$(mk_input "Edit" "README.md")
  start=$(gdate +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  echo "$INPUT" | "$HOOK" >/dev/null 2>&1
  end=$(gdate +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  elapsed_ms=$(( (end - start) / 1000000 ))
  echo "elapsed: ${elapsed_ms}ms"
  [ "$elapsed_ms" -lt 100 ]
}
