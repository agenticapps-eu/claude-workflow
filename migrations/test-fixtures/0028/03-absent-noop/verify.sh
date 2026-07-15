#!/bin/sh
# Verify migration 0028 does NOT create a .prettierignore when none exists
# (append-if-exists), while Step 2 still bumps the version.
set -eu

PI=.prettierignore
SKILL=.claude/skills/agentic-apps-workflow/SKILL.md

[ ! -e "$PI" ] || { echo "PRE: fixture must start with no .prettierignore"; exit 1; }

# ── Step 1 apply — extracted from the migration doc, not copied here ─────────
. "$REPO_ROOT/migrations/test-fixtures/0028/common-verify.sh"

apply_step2() {
  sed 's/^version: 2\.5\.0$/version: 2.6.0/' "$SKILL" > "$SKILL.t" && mv "$SKILL.t" "$SKILL"
}

apply_step1
apply_step2

# Step 1 must NOT have created the file.
[ ! -e "$PI" ] || { echo "STEP1 wrong: created a .prettierignore where none existed"; exit 1; }
# Step 2 still applies (version bump is unconditional).
grep -q '^version: 2\.6\.0$' "$SKILL" || { echo "STEP2 failed: version not bumped"; exit 1; }

echo "OK: 0028 skips a project with no .prettierignore (does not create one); version still bumped"
exit 0
