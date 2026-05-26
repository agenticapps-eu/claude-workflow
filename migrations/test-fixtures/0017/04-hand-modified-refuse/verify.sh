#!/usr/bin/env bash
# Verify fixture 04: refuse path. Script exits 2 (refused); NO destinations
# adapters written; wrapper index.ts unchanged; .observability-0017.patch
# produced; SKILL.md version NOT bumped (abort = no mutation of project state
# beyond the recovery patch artefact).
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"

cp src/lib/observability/index.ts /tmp/0017f04-index.before

# Precondition: the wrapper is REALISTICALLY SUBSTITUTED (no raw {{TOKENS}}
# left) and carries the hand-edit. Refuse must therefore survive correct
# canonicalisation — not be a side effect of an un-substituted template.
grep -q '{{' src/lib/observability/index.ts \
  && { echo "fixture 04 precondition: wrapper still has raw {{tokens}} — not a substituted wrapper"; exit 1; }
grep -q 'HAND-EDIT' src/lib/observability/index.ts \
  || { echo "fixture 04 precondition: hand-edit marker missing"; exit 1; }
grep -q 'SENTRY_DSN' src/lib/observability/index.ts \
  || { echo "fixture 04 precondition: expected substituted DSN env var name"; exit 1; }

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "expected non-zero exit (refuse), got $rc"; exit 1; }

# NO wrapper files written.
test ! -d src/lib/observability/destinations \
  || { echo "REFUSE VIOLATION: destinations/ dir was created"; exit 1; }
test ! -f src/lib/observability/destinations/registry.ts \
  || { echo "REFUSE VIOLATION: registry.ts written"; exit 1; }

# Wrapper itself unchanged (no rewrite to template).
diff -q /tmp/0017f04-index.before src/lib/observability/index.ts >/dev/null \
  || { echo "REFUSE VIOLATION: wrapper index.ts was rewritten"; exit 1; }

# Recovery patch produced.
test -f src/lib/observability/.observability-0017.patch \
  || { echo "refuse-path .observability-0017.patch not generated"; exit 1; }
test -s src/lib/observability/.observability-0017.patch \
  || { echo ".observability-0017.patch is empty"; exit 1; }

# Version NOT bumped on the refuse (abort) path.
grep -q '^version: 1.15.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "REFUSE VIOLATION: version bumped despite abort"; exit 1; }

rm -f /tmp/0017f04-index.before
echo "fixture 04 OK — refused, no wrapper files written, patch produced, version not bumped"
