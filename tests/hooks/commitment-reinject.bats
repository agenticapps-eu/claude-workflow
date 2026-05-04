#!/usr/bin/env bats
# Tests for commitment-reinject.sh (Hook 5)
#
# This hook fires on SessionStart matcher: compact and re-injects the
# AgenticApps commitment contract after compaction. Spec source:
# tooling-research-2026-05-02-batch2.md §3 Hook 5.
#
# Test fixtures spin up tmp dirs with various .planning + CLAUDE.md
# combinations so the hook is exercised against every cwd shape it
# might see in the wild.

# Resolve the script under test (worktree root → hooks)
HOOK="$BATS_TEST_DIRNAME/../../../../../Sourcecode/claude-workflow/.."
# Better: use the live install path
HOOK="$HOME/.claude/hooks/commitment-reinject.sh"

setup() {
  TMPDIR=$(mktemp -d -t commitment-reinject-test-XXXXXX)
  cd "$TMPDIR"
}

teardown() {
  cd /
  rm -rf "$TMPDIR"
}

@test "no .planning → exit 0, no output" {
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test ".planning/ exists, no CLAUDE.md, no phase → emits header only" {
  mkdir -p .planning
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Re-injected after compaction"* ]]
  [[ "$output" == *"$TMPDIR"* ]]
}

@test ".planning/ + CLAUDE.md → emits header + first 50 lines of CLAUDE.md" {
  mkdir -p .planning
  printf 'line %d\n' {1..100} > CLAUDE.md
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"line 1"* ]]
  [[ "$output" == *"line 50"* ]]
  [[ "$output" != *"line 51"* ]]
  [[ "$output" == *"---"* ]]   # separator after CLAUDE.md
}

@test ".planning/ + phases/NN-foo/COMMITMENT.md → emits commitment block" {
  mkdir -p .planning/phases/01-foo
  echo "I am committed to TDD on this phase." > .planning/phases/01-foo/COMMITMENT.md
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Current phase commitment"* ]]
  [[ "$output" == *"01-foo"* ]]
  [[ "$output" == *"committed to TDD"* ]]
}

@test "multiple phase dirs → uses highest-numbered" {
  mkdir -p .planning/phases/01-old .planning/phases/02-current .planning/phases/03-newest
  echo "OLD" > .planning/phases/01-old/COMMITMENT.md
  echo "CURRENT" > .planning/phases/02-current/COMMITMENT.md
  echo "NEWEST" > .planning/phases/03-newest/COMMITMENT.md
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEWEST"* ]]
  [[ "$output" != *"CURRENT"* ]]
  [[ "$output" != *"OLD"* ]]
}

@test ".planning/phases/ exists but highest dir has no COMMITMENT.md → header + CLAUDE.md only" {
  mkdir -p .planning/phases/01-foo
  printf 'line %d\n' {1..10} > CLAUDE.md
  # No COMMITMENT.md in 01-foo
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"line 1"* ]]
  [[ "$output" != *"Current phase commitment"* ]]
}

@test "latency: under 100ms" {
  mkdir -p .planning
  printf 'line %d\n' {1..50} > CLAUDE.md
  start=$(gdate +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  "$HOOK" >/dev/null
  end=$(gdate +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  elapsed_ms=$(( (end - start) / 1000000 ))
  echo "elapsed: ${elapsed_ms}ms"
  [ "$elapsed_ms" -lt 100 ]
}
