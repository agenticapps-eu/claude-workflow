#!/bin/sh
# Fixture 03 — verify non-symlink conflict refusal: pre-flight #3
# detects the non-symlink at the install path and refuses with exit 3.
set -eu

USER_GLOBAL_LINK="$HOME/.claude/skills/ts-declare-first"

# Pre-flight #1: version 1.14.0 → pass
grep -q '^version: 1\.14\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass"; exit 1; }

# Pre-flight #2: scaffolder source present → pass
test -f "$HOME/.claude/skills/agenticapps-workflow/ts-declare-first/SKILL.md" \
  || { echo "PRE-FLIGHT 2 should pass"; exit 1; }

# Pre-flight #3: conflict detect — path exists AND is NOT a symlink
#   → pre-flight MUST refuse with exit 3.
test -e "$USER_GLOBAL_LINK" \
  || { echo "fixture 03 expects a non-symlink at $USER_GLOBAL_LINK"; exit 1; }
test -L "$USER_GLOBAL_LINK" \
  && { echo "fixture 03 expects NON-symlink (hand-vendored dir)"; exit 1; }

# State assertion: no mutation on abort path.
# The hand-vendored SKILL.md must still be there (Step 1 didn't run).
test -f "$USER_GLOBAL_LINK/SKILL.md" \
  || { echo "STEP 1 should NOT have touched hand-vendored skill on abort path"; exit 1; }
grep -q '^version: 0\.0\.99-hand-vendored$' "$USER_GLOBAL_LINK/SKILL.md" \
  || { echo "hand-vendored SKILL.md should be unchanged on abort path"; exit 1; }

echo "fixture 03 — non-symlink correctly detected; pre-flight would abort exit 3; no mutation"
