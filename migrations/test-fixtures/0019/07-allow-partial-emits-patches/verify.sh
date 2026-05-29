#!/usr/bin/env bash
# Verify fixture 07: --allow-partial applies clean roots, skips dirty root.
# Under --allow-partial, patches emitted for ALL roots (clean AND dirty) for
# reference. Engine exits 0. Version bumped (clean roots were migrated).
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

CLEAN_A="services/clean-a/.observability"
CLEAN_B="services/clean-b/.observability"
DIRTY="services/dirty/.observability"

set +e
out=$(bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" --allow-partial 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected engine exit 0 (allow-partial applied clean roots), got $rc"; printf '%s\n' "$out" | head -10; exit 1; }

# Clean roots received the new production files.
for d in "$CLEAN_A" "$CLEAN_B"; do
  test -f "$d/cron-monitor.ts" \
    || { echo "--allow-partial: cron-monitor.ts not installed at clean root $d"; exit 1; }
  test -f "$d/healthz-snippet.ts" \
    || { echo "--allow-partial: healthz-snippet.ts not installed at clean root $d"; exit 1; }
done

# Dirty root was skipped — no new files installed.
test ! -e "$DIRTY/cron-monitor.ts" \
  || { echo "--allow-partial: cron-monitor.ts incorrectly written to dirty root"; exit 1; }
test ! -e "$DIRTY/healthz-snippet.ts" \
  || { echo "--allow-partial: healthz-snippet.ts incorrectly written to dirty root"; exit 1; }

# D-07 --allow-partial: patches emitted for DIRTY root (always) AND CLEAN roots
# (because --allow-partial opts in to emit-everywhere).
for d in "$CLEAN_A" "$CLEAN_B" "$DIRTY"; do
  test -f "$d/.observability-0019.patch" \
    || { echo "--allow-partial: patch not emitted for $d"; exit 1; }
done

# Version bumped to 1.18.0 (clean roots were successfully migrated).
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "--allow-partial: version not bumped despite clean roots being migrated"; exit 1; }

echo "fixture 07 OK — --allow-partial: 2 clean roots migrated, 1 dirty skipped; patches at all 3 roots; version 1.18.0"
