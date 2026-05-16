#!/bin/sh
# Fixture 02 — stale vendored present (v0.2.1) AND no init.
# Pre-flight #2 (confused-state) does NOT trigger because local version
# (0.2.1) != global version (0.3.2). All 3 steps NEED to apply.
set -eu

# Pre-flight #1: version 1.11.0 → pass
grep -qE '^version: 1\.(11\.0|12\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass"; exit 1; }

# Pre-flight #2: vendored present AND its version differs from global
test -d .claude/skills/add-observability \
  || { echo "fixture 02 expects vendored skill present"; exit 1; }
LOCAL_VER=$(awk '/^version:/{print $2; exit}'  .claude/skills/add-observability/SKILL.md)
GLOBAL_VER=$(awk '/^version:/{print $2; exit}' "$HOME/.claude/skills/agenticapps-workflow/add-observability/SKILL.md")
[ "$LOCAL_VER" = "$GLOBAL_VER" ] \
  && { echo "fixture 02 SHOULD have different versions (local=$LOCAL_VER global=$GLOBAL_VER)"; exit 1; }
# i.e. pre-flight #2 does NOT trigger → migration proceeds.

# Step 1 idempotency: vendored copy exists → NEEDS to apply (remove it)
test ! -e .claude/skills/add-observability \
  && { echo "STEP 1 idempotency wrong (vendored should still be present pre-apply)"; exit 1; }

# Step 2 idempotency: no observability: block → NEEDS to apply
grep -q '^observability:' CLAUDE.md \
  && { echo "STEP 2 idempotency wrong (no observability metadata expected)"; exit 1; }

# Step 3 idempotency: version 1.11.0 → NEEDS to apply
grep -q '^version: 1.12.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 3 idempotency wrong (version still 1.11.0)"; exit 1; }

echo "fixture 02 — pre-flight passes (versions differ); Steps 1, 2, 3 all need to apply"
