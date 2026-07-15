#!/bin/sh
# Verify 0029's Rollback (C2/I5): running Rollback on a HEALED region-led file
# must remove only the §11 block, leaving the region's start/end markers each
# present exactly once and the region's inner content intact. Under the buggy
# terminator (only `^## `, no gitnexus:start alternation), Rollback swallows
# past the start marker and the region's real content, terminating instead at
# the region's OWN first `## ` heading — leaving an orphaned end marker.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

# Pre-condition: §11 sits directly above the region, both markers present once.
prov=$(grep -n 'spec-source: .* §11' CLAUDE.md | cut -d: -f1)
start=$(grep -n '^<!-- gitnexus:start -->$' CLAUDE.md | cut -d: -f1)
[ -n "$prov" ] && [ -n "$start" ] && [ "$prov" -lt "$start" ] || {
  echo "PRE: fixture must start §11-above-region (prov=$prov start=$start)"
  exit 1
}
[ "$(grep -c '^<!-- gitnexus:start -->$' CLAUDE.md)" -eq 1 ] || {
  echo "PRE: expected exactly one start marker before rollback"
  exit 1
}
[ "$(grep -c '^<!-- gitnexus:end -->$' CLAUDE.md)" -eq 1 ] || {
  echo "PRE: expected exactly one end marker before rollback"
  exit 1
}

rollback_step1

grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md && {
  echo "FAIL: Rollback left the §11 heading behind"
  exit 1
}
grep -q 'spec-source: .* §11' CLAUDE.md && {
  echo "FAIL: Rollback left the §11 provenance comment behind"
  exit 1
}

[ "$(grep -c '^<!-- gitnexus:start -->$' CLAUDE.md)" -eq 1 ] || {
  echo "FAIL: gitnexus:start marker damaged by Rollback (this is the destroyed-region bug)"
  exit 1
}
[ "$(grep -c '^<!-- gitnexus:end -->$' CLAUDE.md)" -eq 1 ] || {
  echo "FAIL: gitnexus:end marker damaged by Rollback"
  exit 1
}

# The region's own inner content must survive — this is what "eats the
# region" looks like when the terminator fix is missing.
grep -q 'MUST run impact analysis before editing any symbol' CLAUDE.md || {
  echo "FAIL: region content lost by Rollback (Always Do section)"
  exit 1
}
grep -q 'NEVER rename symbols with find-and-replace' CLAUDE.md || {
  echo "FAIL: region content lost by Rollback (Never Do section)"
  exit 1
}

# Project content below the region must also survive.
grep -q '^## Workflow$' CLAUDE.md || { echo "FAIL: project content lost by Rollback"; exit 1; }

echo "OK: 0029 Rollback removes §11 from a healed region-led file, region intact"
exit 0
