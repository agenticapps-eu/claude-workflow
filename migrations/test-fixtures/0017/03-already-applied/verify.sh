#!/usr/bin/env bash
# Verify fixture 03: idempotent no-op. Script exits 0; the wrapper index.ts is
# byte-unchanged from the pre-run state.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"

# Snapshot the wrapper + CLAUDE.md before re-run.
cp src/lib/observability/index.ts /tmp/0017f03-index.before
cp CLAUDE.md /tmp/0017f03-claude.before

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0 (idempotent), got $rc"; exit 1; }

diff -q /tmp/0017f03-index.before src/lib/observability/index.ts >/dev/null \
  || { echo "wrapper index.ts mutated on idempotent re-run"; exit 1; }
diff -q /tmp/0017f03-claude.before CLAUDE.md >/dev/null \
  || { echo "CLAUDE.md mutated on idempotent re-run"; exit 1; }

rm -f /tmp/0017f03-index.before /tmp/0017f03-claude.before
echo "fixture 03 OK — idempotent no-op, no mutation"
