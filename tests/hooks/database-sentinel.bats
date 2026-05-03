#!/usr/bin/env bats
# Tests for database-sentinel.sh (Hook 1, PreToolUse)
# Spec: synthesis report §3 Hook 1 + handoff prompt Phase 2B.

HOOK="$BATS_TEST_DIRNAME/../../templates/.claude/hooks/database-sentinel.sh"

setup() {
  TMPDIR=$(mktemp -d -t db-sentinel-test-XXXXXX)
  cd "$TMPDIR"
}

teardown() {
  cd /
  rm -rf "$TMPDIR"
}

# Helper: build a tool_input JSON envelope.
mk_bash_input() {
  jq -nc --arg cmd "$1" '{tool_name: "Bash", tool_input: {command: $cmd}}'
}
mk_edit_input() {
  jq -nc --arg path "$1" '{tool_name: "Edit", tool_input: {file_path: $path}}'
}

# === Bash blocks ===

@test "Bash DROP TABLE → blocked (exit 2)" {
  run bash -c "echo '$(mk_bash_input "DROP TABLE users")' | $HOOK"
  [ "$status" -eq 2 ]
  [[ "$stderr_or_output" == *"DROP/TRUNCATE"* ]] || [[ "$output" == *"DROP/TRUNCATE"* ]]
}

@test "Bash TRUNCATE TABLE → blocked (exit 2)" {
  run bash -c "echo '$(mk_bash_input "TRUNCATE TABLE foo")' | $HOOK"
  [ "$status" -eq 2 ]
}

@test "Bash DELETE FROM table without WHERE → blocked (exit 2)" {
  run bash -c "echo '$(mk_bash_input "DELETE FROM users;")' | $HOOK"
  [ "$status" -eq 2 ]
}

@test "Bash DELETE FROM table WITH WHERE → allowed (exit 0)" {
  run bash -c "echo '$(mk_bash_input "DELETE FROM users WHERE id=1;")' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "Bash SELECT → allowed (exit 0)" {
  run bash -c "echo '$(mk_bash_input "SELECT * FROM users")' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "Bash random non-SQL → allowed (exit 0)" {
  run bash -c "echo '$(mk_bash_input "ls -la")' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "Bash drop table (lowercase) → blocked (exit 2)" {
  run bash -c "echo '$(mk_bash_input "drop table foo")' | $HOOK"
  [ "$status" -eq 2 ]
}

# === Edit/Write blocks ===

@test "Edit .env → blocked (exit 2)" {
  run bash -c "echo '$(mk_edit_input ".env")' | $HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"env file"* ]]
}

@test "Edit .env.production → blocked (exit 2)" {
  run bash -c "echo '$(mk_edit_input ".env.production")' | $HOOK"
  [ "$status" -eq 2 ]
}

@test "Edit project/.env.local → blocked (exit 2)" {
  run bash -c "echo '$(mk_edit_input "project/.env.local")' | $HOOK"
  [ "$status" -eq 2 ]
}

@test "Edit .env.example → allowed (exit 0)" {
  run bash -c "echo '$(mk_edit_input ".env.example")' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "Edit .env.template → allowed (exit 0)" {
  run bash -c "echo '$(mk_edit_input ".env.template")' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "Edit migrations/001.sql without sentinel → blocked (exit 2)" {
  run bash -c "echo '$(mk_edit_input "migrations/001_create_users.sql")' | $HOOK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"migration"* ]]
}

@test "Edit migrations/001.sql WITH sentinel → allowed (exit 0)" {
  mkdir -p .planning/current-phase
  touch .planning/current-phase/migrations-approved
  run bash -c "echo '$(mk_edit_input "migrations/001_create_users.sql")' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "Edit src/components/Foo.tsx → allowed (out of scope for Hook 1)" {
  run bash -c "echo '$(mk_edit_input "src/components/Foo.tsx")' | $HOOK"
  [ "$status" -eq 0 ]
}

# === Latency ===

@test "latency: under 100ms" {
  INPUT=$(mk_bash_input "ls -la")
  start=$(gdate +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  echo "$INPUT" | "$HOOK" >/dev/null 2>&1
  end=$(gdate +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  elapsed_ms=$(( (end - start) / 1000000 ))
  echo "elapsed: ${elapsed_ms}ms"
  [ "$elapsed_ms" -lt 100 ]
}
