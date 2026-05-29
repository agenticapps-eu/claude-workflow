#!/usr/bin/env bash
# Verify fixture 06 (R09 binding + D-07 honest reframe): atomic refuse across
# mixed clean+dirty wrappers.
# - None of the three roots gets cron-monitor.ts (atomic refusal).
# - Recovery patch emitted for DIRTY root only (D-07 default: clean roots NOT patched).
# - Engine exits 2; version not bumped.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

CLEAN_A="services/clean-a/.observability"
CLEAN_B="services/clean-b/.observability"
DIRTY="services/dirty/.observability"

cp "$DIRTY/middleware.ts" /tmp/0019f06-dirty.before

set +e
out=$(bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "expected engine exit 2 (refuse), got $rc"; printf '%s\n' "$out" | head -10; exit 1; }

# NONE of the three roots got the new files — atomic refusal.
for d in "$CLEAN_A" "$CLEAN_B" "$DIRTY"; do
  test ! -e "$d/cron-monitor.ts" \
    || { echo "ATOMIC REFUSE VIOLATION: $d/cron-monitor.ts written"; exit 1; }
  test ! -e "$d/healthz-snippet.ts" \
    || { echo "ATOMIC REFUSE VIOLATION: $d/healthz-snippet.ts written"; exit 1; }
done

# D-07 (R-rev-5 honest reframe): DEFAULT refuse writes patch to DIRTY root only.
# CLEAN roots must NOT receive .observability-0019.patch in default mode.
test -f "$DIRTY/.observability-0019.patch" \
  || { echo "patch not emitted for DIRTY root"; exit 1; }
test -s "$DIRTY/.observability-0019.patch" \
  || { echo "patch empty at DIRTY root"; exit 1; }
for d in "$CLEAN_A" "$CLEAN_B"; do
  test ! -e "$d/.observability-0019.patch" \
    || { echo "D-07 VIOLATION: patch emitted to clean root $d in DEFAULT refuse path"; exit 1; }
done

# Dirty root's middleware.ts unchanged — engine wrote nothing into ANY root.
diff -q /tmp/0019f06-dirty.before "$DIRTY/middleware.ts" >/dev/null \
  || { echo "ATOMIC REFUSE VIOLATION: dirty middleware.ts was rewritten"; exit 1; }

# Engine output names the dirty root.
echo "$out" | grep -q "$DIRTY"   || { echo "engine output missing dirty-root path"; exit 1; }
# Engine output also lists clean roots (informational, but must mention them).
echo "$out" | grep -q "$CLEAN_A" || { echo "engine output missing would-be-clean path (clean-a)"; exit 1; }
echo "$out" | grep -q "$CLEAN_B" || { echo "engine output missing would-be-clean path (clean-b)"; exit 1; }

# Version NOT bumped on the refuse path.
grep -q '^version: 1.17.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "REFUSE VIOLATION: version bumped despite atomic refuse"; exit 1; }

rm -f /tmp/0019f06-dirty.before
echo "fixture 06 OK — atomic refuse 2 clean + 1 dirty; patch only at DIRTY root (D-07 default); version unchanged"
