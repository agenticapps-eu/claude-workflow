#!/bin/sh
# Fixture 04 — pre-flight #4 must HARD ABORT. NO version bump path.
set -eu

# Pre-flight #1: version is fine (1.10.0)
grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass — fixture issue"; exit 1; }
# Pre-flight #2: scaffolder add-observability dir exists
test -d "$HOME/.claude/skills/agenticapps-workflow/add-observability" \
  || { echo "PRE-FLIGHT 2 should pass — fixture issue"; exit 1; }
# Pre-flight #3: target exists AND is a symlink → no real-dir clobber
if [ -e "$HOME/.claude/skills/add-observability" ] && [ ! -L "$HOME/.claude/skills/add-observability" ]; then
  echo "PRE-FLIGHT 3 — fixture should have symlink not dir"; exit 1
fi
# Pre-flight #4: existing symlink with WRONG target → must abort
test -L "$HOME/.claude/skills/add-observability" \
  || { echo "fixture 04 expects symlink to exist before verify"; exit 1; }
EXISTING=$(readlink "$HOME/.claude/skills/add-observability")
case "$EXISTING" in
  */agenticapps-workflow/add-observability)
    echo "PRE-FLIGHT 4 wrong: symlink points at scaffolder (should be wrong-target)"
    exit 1
    ;;
  *)
    # Correct fixture state: wrong target. Pre-flight would HARD ABORT
    # exit 3 here. Verify that:
    #   1. version is NOT bumped (no Step 3 happens on this path)
    #   2. symlink is NOT replaced (Step 1 doesn't run either)
    grep -q '^version: 1.11.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
      && { echo "STEP 3 should NOT have run on abort path (version still 1.10.0)"; exit 1; }
    readlink "$HOME/.claude/skills/add-observability" | grep -q '/agenticapps-workflow/add-observability$' \
      && { echo "STEP 1 should NOT have replaced the wrong-target symlink on abort path"; exit 1; }
    echo "fixture 04 — wrong-target symlink correctly preserved; no version bump (abort path)"
    exit 0
    ;;
esac
