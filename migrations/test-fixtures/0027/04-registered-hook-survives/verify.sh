#!/bin/sh
# Verify migration 0027 Step 5's fail-safe branch (fixture 04): a project that
# deliberately REGISTERED observability-postphase-scan.sh in a settings.json
# event keeps it. Step 5 removes a hook only when it is present AND bound to no
# event — it must never delete a hook someone wired on purpose.
#
# This fixture is the negative twin of fixture 01's Step 5: 01 proves the hook
# IS removed when dead, 04 proves it is NOT removed when live. Without 04, a
# Step 5 that unconditionally `rm -f`s would still pass the suite.
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

HOOK=.claude/hooks/observability-postphase-scan.sh

# Pre-conditions: hook present AND registered.
[ -e "$HOOK" ] || { echo "PRE: fixture must carry the hook on disk"; exit 1; }
jq -e '[.hooks // {} | .[]? | .[]? | .hooks[]? | .command?]
       | map(select(type == "string"))
       | map(select(test("observability-postphase-scan\\.sh")))
       | length > 0' .claude/settings.json >/dev/null \
  || { echo "PRE: fixture must register the hook"; exit 1; }

# ── Step 5 (apply) — registered => SKIP ─────────────────────────────────────
if [ -e "$HOOK" ]; then
  REGISTERED=0
  if [ -f .claude/settings.json ] && jq empty .claude/settings.json 2>/dev/null; then
    if jq -e '[.hooks // {} | .[]? | .[]? | .hooks[]? | .command?]
              | map(select(type == "string"))
              | map(select(test("observability-postphase-scan\\.sh")))
              | length > 0' .claude/settings.json >/dev/null 2>&1; then
      REGISTERED=1
    fi
  fi
  if [ "$REGISTERED" -eq 1 ]; then
    echo "SKIP: $HOOK is registered in .claude/settings.json — leaving it in place."
  else
    rm -f "$HOOK"
  fi
fi

# THE assertion: the registered hook survived, still executable.
[ -x "$HOOK" ] \
  || { echo "STEP 5 failed: deleted a REGISTERED hook — fail-safe branch broken"; exit 1; }

# And its registration was not touched either.
jq -e '[.hooks // {} | .[]? | .[]? | .hooks[]? | .command?]
       | map(select(type == "string"))
       | map(select(test("observability-postphase-scan\\.sh")))
       | length > 0' .claude/settings.json >/dev/null \
  || { echo "STEP 5 failed: unregistered a live hook"; exit 1; }

echo "OK: 0027 Step 5 leaves a registered hook in place"
exit 0
