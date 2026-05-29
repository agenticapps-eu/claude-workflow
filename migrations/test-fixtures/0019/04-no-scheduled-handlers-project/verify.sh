#!/usr/bin/env bash
# Verify fixture 04 (cparx-shape): worker wrapper exists, no scheduled handler
# wired in the entry file. Migration still applies because the exports are
# opt-in and the engine only inspects the wrapper directory. Entry file
# survives untouched.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

ROOT="src/lib/observability"

# Preserve a hash of the operator's entry file so we can assert immutability.
if command -v sha256sum >/dev/null 2>&1; then
  entry_before=$(sha256sum src/index.ts | awk '{print $1}')
else
  entry_before=$(shasum -a 256 src/index.ts | awk '{print $1}')
fi

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; exit 1; }

# Wrapper-dir additions present (clean apply).
test -f "$ROOT/cron-monitor.ts"    || { echo "cron-monitor.ts not installed"; exit 1; }
test -f "$ROOT/healthz-snippet.ts" || { echo "healthz-snippet.ts not installed"; exit 1; }

# Operator's entry file MUST be byte-identical (engine never touches it).
if command -v sha256sum >/dev/null 2>&1; then
  entry_after=$(sha256sum src/index.ts | awk '{print $1}')
else
  entry_after=$(shasum -a 256 src/index.ts | awk '{print $1}')
fi
[ "$entry_before" = "$entry_after" ] \
  || { echo "ENTRY VIOLATION: src/index.ts mutated by migration"; exit 1; }

# Entry file still has no scheduled() export — the migration did not retrofit
# the operator's wiring (opt-in is opt-in). Use `if grep` to keep set -e happy
# when grep "succeeds by not matching" — the cleanly-passing case.
if grep -q '^[[:space:]]*scheduled' src/index.ts; then
  echo "ENTRY VIOLATION: migration retrofitted a scheduled() export"; exit 1
fi

# Version bumped to 1.18.0.
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version not bumped to 1.18.0"; exit 1; }

echo "fixture 04 OK — cparx-shape: wrapper migrated, operator entry untouched, version 1.18.0"
