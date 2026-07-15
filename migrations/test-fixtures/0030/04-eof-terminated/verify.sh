#!/bin/sh
# Verify 0030 heals an EOF-terminated stale block with no trailing-byte
# churn: the healed file must be EXACTLY [everything through the provenance
# line] + [the mirror's bytes verbatim] — nothing appended, nothing dropped.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

cp CLAUDE.md CLAUDE.md.before

check_step1_idempotent && { echo "FAIL: idempotency check passed on a STALE block"; exit 1; }

apply_step1

prov_line=$(grep -n '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md.before | cut -d: -f1)
[ -n "$prov_line" ] || { echo "PRE: could not find provenance line in BEFORE"; exit 1; }

head -n "$prov_line" CLAUDE.md.before > expected.md
cat "$MIRROR" >> expected.md

diff expected.md CLAUDE.md || {
  echo "FAIL: EOF-terminated block did not heal to exactly [prefix through"
  echo "      the provenance line + mirror bytes] — trailing-byte churn or"
  echo "      an incomplete heal. Diff:"
  diff expected.md CLAUDE.md || true
  exit 1
}

echo "OK: EOF-terminated stale block healed to mirror bytes with no"
echo "    trailing-byte churn"
exit 0
