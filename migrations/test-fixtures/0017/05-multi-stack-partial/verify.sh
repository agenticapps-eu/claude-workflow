#!/usr/bin/env bash
# Verify fixture 05: both modes.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"

CLEAN_ROOT="web/src/lib/observability"
DIRTY_ROOT="api/src/lib/observability"

# ── Mode 1: DEFAULT (all-clean gate) — ZERO writes to EITHER root, non-zero ──
cp "$CLEAN_ROOT/index.ts" /tmp/0017f05-clean.before
cp "$DIRTY_ROOT/index.ts" /tmp/0017f05-dirty.before

set +e
out=$(bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "DEFAULT: expected non-zero (abort), got $rc"; exit 1; }

# ZERO writes to EITHER root.
test ! -d "$CLEAN_ROOT/destinations" || { echo "DEFAULT VIOLATION: clean root migrated despite all-clean gate"; exit 1; }
test ! -d "$DIRTY_ROOT/destinations" || { echo "DEFAULT VIOLATION: dirty root migrated"; exit 1; }
diff -q /tmp/0017f05-clean.before "$CLEAN_ROOT/index.ts" >/dev/null || { echo "DEFAULT VIOLATION: clean wrapper rewritten"; exit 1; }
diff -q /tmp/0017f05-dirty.before "$DIRTY_ROOT/index.ts" >/dev/null || { echo "DEFAULT VIOLATION: dirty wrapper rewritten"; exit 1; }
# Version NOT bumped under default-abort.
grep -q '^version: 1.15.0$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "DEFAULT VIOLATION: version bumped on abort"; exit 1; }
# Both roots surfaced to the operator (dirty offender + clean would-migrate list).
echo "$out" | grep -q "$DIRTY_ROOT" || { echo "DEFAULT: dirty root not listed"; exit 1; }
echo "$out" | grep -q "$CLEAN_ROOT" || { echo "DEFAULT: clean root not listed in would-migrate"; exit 1; }

# ── Mode 2: --allow-partial — clean migrated, dirty skipped + listed, non-zero ──
set +e
out2=$(bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" --allow-partial 2>&1)
rc2=$?
set -e
[ "$rc2" -ne 0 ] || { echo "ALLOW-PARTIAL: expected non-zero, got $rc2"; exit 1; }

# Clean root migrated.
test -f "$CLEAN_ROOT/destinations/registry.ts" || { echo "ALLOW-PARTIAL: clean root not migrated"; exit 1; }
grep -q 'buildRegistry' "$CLEAN_ROOT/index.ts" || { echo "ALLOW-PARTIAL: clean wrapper not dispatched"; exit 1; }
# Dirty root NOT migrated (skipped).
test ! -d "$DIRTY_ROOT/destinations" || { echo "ALLOW-PARTIAL VIOLATION: dirty root migrated"; exit 1; }
# Dirty root listed as skipped.
echo "$out2" | grep -q "$DIRTY_ROOT" || { echo "ALLOW-PARTIAL: dirty root not listed as skipped"; exit 1; }
# Version bumped (clean apply happened).
grep -q '^version: 1.16.0$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "ALLOW-PARTIAL: version not bumped after partial apply"; exit 1; }

rm -f /tmp/0017f05-clean.before /tmp/0017f05-dirty.before
echo "fixture 05 OK — default aborts (zero writes both), --allow-partial migrates clean only"
