#!/bin/sh
# Verify 0029's marker regexes are anchored (C1): a file whose ONLY mention of
# `<!-- gitnexus:start -->` is prose inside a guard comment must be judged
# already-applied by the idempotency check, and Apply must be a byte-identical
# no-op — not an injection into the comment.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

# Pre-condition: the file has no REAL region (no line that IS exactly the
# marker), but does contain a prose mention of it.
awk '/^<!-- gitnexus:start -->$/ { found=1 } END { exit(found ? 1 : 0) }' CLAUDE.md || {
  echo "PRE: fixture must contain no anchored gitnexus:start marker line"
  exit 1
}
grep -q 'gitnexus:start' CLAUDE.md || {
  echo "PRE: fixture must still mention gitnexus:start in prose"
  exit 1
}

before="$(cat CLAUDE.md)"

# The idempotency check itself must report "already applied" (exit 0). Under
# the unanchored-regex bug this returns non-zero — it judges the prose mention
# as "inside a region".
check_step1_idempotent || {
  echo "FAIL: idempotency check does not treat a prose mention as already-applied"
  exit 1
}

apply_step1

[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: 0029 modified a file whose only marker mention is prose. Diff:"
  printf '%s\n' "$before" > CLAUDE.md.before
  diff CLAUDE.md.before CLAUDE.md || true
  exit 1
}

# Specifically: the guard comment must not have gained an injected §11 block
# inside it (the exact failure mode of the unanchored regex).
n=$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)
[ "$n" -eq 1 ] || { echo "FAIL: §11 heading appears $n times, expected 1"; exit 1; }

echo "OK: 0029 treats a prose mention of the marker as prose, not a region"
exit 0
