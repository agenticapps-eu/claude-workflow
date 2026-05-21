#!/bin/sh
# Fixture 05 — verify no-claudemd state: pre-flight permissive on missing
# CLAUDE.md (same idiom as 0013 Step 2); Step 1 no-ops with informational
# message; Step 2 still needs to apply (version bump).
set -eu

# Pre-flight #1: version 1.12.0 → pass
grep -qE '^version: 1\.(12\.0|14\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass"; exit 1; }

# Pre-flight #2: vendored block present → pass
test -f "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md" \
  || { echo "PRE-FLIGHT 2 should pass"; exit 1; }

# Pre-flight #3: conflict detect — short-circuits on missing CLAUDE.md.
# The [ -f CLAUDE.md ] && grep ... chain returns non-zero overall, which
# means "no conflict detected" (correct behavior — there's no file to
# conflict with).
test ! -f CLAUDE.md \
  || { echo "fixture 05 expects no CLAUDE.md"; exit 1; }

# Step 1 idempotency: no CLAUDE.md → permissive no-op path. The check
# expression itself short-circuits on the missing file.
# Verify the file is genuinely absent (so the migration's apply branch
# correctly enters the informational-no-op path).
test ! -f CLAUDE.md \
  || { echo "STEP 1 should see no CLAUDE.md to operate on"; exit 1; }

# Step 2 idempotency: version still 1.12.0 → NEEDS apply
grep -q '^version: 1\.14\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 2 idempotency wrong (version still 1.12.0 expected)"; exit 1; }

echo "fixture 05 — no CLAUDE.md; Step 1 takes informational no-op path; Step 2 needs apply"
