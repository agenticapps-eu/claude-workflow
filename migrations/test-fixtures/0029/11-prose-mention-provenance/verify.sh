#!/bin/sh
# Verify 0029's PROV_RE is anchored (I-1): a file whose guard comment MENTIONS
# the provenance marker in prose, above the real (correctly placed) block,
# must be judged already-applied, and Apply must be a byte-identical no-op —
# not a strip pass that enters `in_block` at the prose line and destroys
# everything between it and the block's own heading.
#
# Under the unanchored-regex bug, apply_step1 below turns this fixture's
# 91-line input into 85 lines: it deletes the guard comment's closing lines
# AND the "IMPORTANT PROJECT RULE" content between the prose mention and the
# real marker, then re-inserts the provenance line mid-comment (right after
# "The §11 block is anchored behind"), breaking the HTML comment structure.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

# Pre-condition: no real GitNexus region, a prose mention of the provenance
# marker above the real one (two occurrences of the marker substring total),
# and the project rule content that must survive.
awk '/^<!-- gitnexus:start -->$/ { found=1 } END { exit(found ? 1 : 0) }' CLAUDE.md || {
  echo "PRE: fixture must contain no anchored gitnexus:start marker line"
  exit 1
}
n_marker=$(grep -c 'spec-source: agenticapps-workflow-core@0\.4\.0 §11' CLAUDE.md)
[ "$n_marker" -eq 2 ] || {
  echo "PRE: fixture must mention the provenance marker twice (prose + real), found $n_marker"
  exit 1
}
grep -q 'IMPORTANT PROJECT RULE' CLAUDE.md || {
  echo "PRE: fixture must carry the project rule content that the bug destroys"
  exit 1
}

before="$(cat CLAUDE.md)"

# The idempotency check itself must report "already applied" (exit 0) — the
# real block is present and correctly placed; there is no GitNexus region for
# it to be "inside."
check_step1_idempotent || {
  echo "FAIL: idempotency check does not treat this healthy file as already-applied"
  exit 1
}

apply_step1

[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: 0029 modified a file whose extra marker mention is prose. Diff:"
  printf '%s\n' "$before" > CLAUDE.md.before
  diff CLAUDE.md.before CLAUDE.md || true
  exit 1
}

# Specifically: the project rule must survive (the strip pass must not have
# swallowed it), the guard comment must not have gained an injected §11
# provenance line inside it, and there must be exactly one §11 block.
grep -q 'IMPORTANT PROJECT RULE' CLAUDE.md || {
  echo "FAIL: project rule content was destroyed by the strip pass"
  exit 1
}
n=$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)
[ "$n" -eq 1 ] || { echo "FAIL: §11 heading appears $n times, expected 1"; exit 1; }
grep -q '^-->$' CLAUDE.md || {
  echo "FAIL: guard comment's closing '-->' is gone — the comment was broken"
  exit 1
}

echo "OK: 0029 treats a prose mention of the provenance marker as prose, not the block"
exit 0
