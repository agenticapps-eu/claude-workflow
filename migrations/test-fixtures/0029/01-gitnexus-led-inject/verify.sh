#!/bin/sh
# Verify 0029 on a gitnexus-led CLAUDE.md with no §11 block: the block is
# injected ABOVE the managed region, and survives a region regeneration.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

# Pre-condition: no §11, and the first `## ` is inside the region.
grep -q 'Coding Discipline' CLAUDE.md && { echo "PRE: §11 must be absent"; exit 1; }

apply_step1

prov=$(grep -n 'spec-source: agenticapps-workflow-core@0.4.0 §11' CLAUDE.md | cut -d: -f1)
start=$(grep -n 'gitnexus:start' CLAUDE.md | cut -d: -f1)
[ -n "$prov" ] || { echo "FAIL: §11 block not injected"; exit 1; }
[ "$prov" -lt "$start" ] || {
  echo "FAIL: §11 injected at L$prov, at/below region start L$start — this is the bug"
  exit 1
}

# Exactly one block.
n=$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)
[ "$n" -eq 1 ] || { echo "FAIL: §11 heading appears $n times, expected 1"; exit 1; }

# The point of the migration: survive a region regeneration.
awk '
  /<!-- gitnexus:start -->/ { print; skip=1; print "# GitNexus — Code Intelligence"; print ""
                              print "## Always Do"; print "- regenerated"; next }
  /<!-- gitnexus:end -->/   { skip=0 }
  !skip { print }
' CLAUDE.md > CLAUDE.md.analyzed && mv CLAUDE.md.analyzed CLAUDE.md

grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md || {
  echo "FAIL: §11 destroyed by a modelled gitnexus analyze"
  exit 1
}

echo "OK: 0029 injects §11 above the region on a gitnexus-led file; survives analyze"
exit 0
