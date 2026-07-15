#!/bin/sh
# Verify 0029 moves an at-risk §11 block from inside the region to above it,
# leaving exactly one copy and an intact region.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

# Pre-condition: the block starts INSIDE the region.
prov=$(grep -n 'spec-source: .* §11' CLAUDE.md | cut -d: -f1)
start=$(grep -n 'gitnexus:start' CLAUDE.md | cut -d: -f1)
end=$(grep -n 'gitnexus:end' CLAUDE.md | cut -d: -f1)
[ "$prov" -gt "$start" ] && [ "$prov" -lt "$end" ] || {
  echo "PRE: fixture must start with §11 INSIDE the region (prov=$prov start=$start end=$end)"
  exit 1
}

apply_step1

prov=$(grep -n 'spec-source: .* §11' CLAUDE.md | cut -d: -f1)
start=$(grep -n 'gitnexus:start' CLAUDE.md | cut -d: -f1)
[ "$prov" -lt "$start" ] || { echo "FAIL: §11 still at/below region start (prov=$prov start=$start)"; exit 1; }

n=$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)
[ "$n" -eq 1 ] || { echo "FAIL: §11 heading appears $n times after move, expected 1"; exit 1; }

# Region markers intact and still paired.
[ "$(grep -c 'gitnexus:start' CLAUDE.md)" -eq 1 ] || { echo "FAIL: start marker damaged"; exit 1; }
[ "$(grep -c 'gitnexus:end' CLAUDE.md)" -eq 1 ] || { echo "FAIL: end marker damaged"; exit 1; }
# Region content preserved.
grep -q 'MUST run impact analysis' CLAUDE.md || { echo "FAIL: region content lost"; exit 1; }
# Project content preserved.
grep -q '^## Workflow$' CLAUDE.md || { echo "FAIL: project content lost"; exit 1; }

echo "OK: 0029 moves an inside-region §11 block above the region, exactly once"
exit 0
