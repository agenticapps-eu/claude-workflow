#!/usr/bin/env bash
# A project that already owns .git/hooks/pre-commit must not silently lose it.
# Step 1 installs OUR floor there, so the prior hook is preserved beside it and
# the operator is told to merge. Losing a project's commit hook without a word
# is exactly the class of silent data loss this repo keeps writing guards for.
set -uo pipefail
fail() { echo "FAIL: $*"; exit 1; }

hooks_dir="$(git rev-parse --git-path hooks)"
grep -q 'project OWNS this hook' "$hooks_dir/pre-commit" || fail "PRE: expected the project's own hook"

out=$(. "$FIXTURES_ROOT/common-apply.sh" 2>&1)

printf '%s' "$out" | grep -q 'saved as pre-commit.pre-0032' \
  || fail "apply did not REPORT that it displaced the project's hook: $out"
[ -e "$hooks_dir/pre-commit.pre-0032" ] || fail "the project's hook was not preserved"
grep -q 'project OWNS this hook' "$hooks_dir/pre-commit.pre-0032" \
  || fail "the preserved copy is not the project's original"
grep -q 'openspec-change-gate' "$hooks_dir/pre-commit" || fail "our floor was not installed"

. "$FIXTURES_ROOT/common-verify.sh"
echo OK
