#!/bin/sh
# Verify 0030 heals the block and leaves a GitNexus-managed region that has
# no `## ` heading between it and the block byte-identical — including the
# region's OWN `## Always Do` line, which a heading-only terminator (missing
# the `gitnexus:start` alternation) would misread as the block's terminator
# and destroy the region past that point.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

extract_region() {
  awk '/^<!-- gitnexus:start -->$/{f=1} f{print} f && /^<!-- gitnexus:end -->$/{exit}' "$1"
}

extract_region CLAUDE.md > region.before
[ -s region.before ] || { echo "PRE: could not extract the gitnexus region from BEFORE"; exit 1; }
grep -q '^## Always Do$' region.before || { echo "PRE: region.before is missing its '## Always Do' line"; exit 1; }

check_step1_idempotent && { echo "FAIL: idempotency check passed on a STALE block"; exit 1; }

apply_step1

extract_region CLAUDE.md > region.after
diff region.before region.after || { echo "FAIL: gitnexus region was altered by the §11 re-sync"; exit 1; }

grep -q '^## Always Do$' region.after || {
  echo "FAIL: region body's '## Always Do' line lost — a heading-only"
  echo "      terminator would have mistaken it for the block terminator"
  echo "      and run the replacement straight through the region"
  exit 1
}

awk '/^## Coding Discipline \(NON-NEGOTIABLE\)$/{f=1} f{print} f && /session-level discipline the model brings to every diff\.$/{exit}' CLAUDE.md > got.md
diff "$MIRROR" got.md || { echo "FAIL: block did not heal to mirror bytes"; exit 1; }

echo "OK: block healed to mirror bytes; gitnexus region (including its own"
echo "    '## Always Do' line) left byte-identical"
exit 0
