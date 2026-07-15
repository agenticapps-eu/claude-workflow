#!/bin/sh
# Verify migration 0028 against a project whose .prettierignore already ignores
# the whole .claude directory. That entry subsumes .claude/hooks/, so Step 1
# must recognise the work as already done and append NOTHING. Appending a
# redundant .claude/hooks/ under a bare .claude adds noise to a project file
# for no formatting effect.
#
# Like the other 0028 fixtures, this one runs Step 1's Apply block extracted
# from the migration document (see common-verify.sh) rather than a copy, so the
# predicate fix has to land in the document to make this fixture pass.
set -eu

PI=.prettierignore
SKILL=.claude/skills/agentic-apps-workflow/SKILL.md

# Pre-condition: a .prettierignore with a bare `.claude` and no `.claude/hooks`.
[ -f "$PI" ] || { echo "PRE: fixture must have a .prettierignore"; exit 1; }
grep -qE '^\.claude$' "$PI" || { echo "PRE: fixture must ignore bare .claude"; exit 1; }
grep -qE '^\.claude/hooks/?$' "$PI" && { echo "PRE: .claude/hooks must be absent before apply"; exit 1; }

# ── Step 1 apply — extracted from the migration doc, not copied here ─────────
. "$REPO_ROOT/migrations/test-fixtures/0028/common-verify.sh"

apply_step2() {
  sed 's/^version: 2\.5\.0$/version: 2.6.0/' "$SKILL" > "$SKILL.t" && mv "$SKILL.t" "$SKILL"
}

before_pi="$(cat "$PI")"

apply_step1 >/dev/null 2>&1
apply_step2

# Step 1: nothing appended — a bare `.claude` already covers .claude/hooks/.
if [ "$before_pi" != "$(cat "$PI")" ]; then
  echo "STEP1 failed: .prettierignore was modified, but bare '.claude' already"
  echo "              subsumes .claude/hooks/. Diff:"
  printf '%s\n' "$before_pi" > /tmp/0028-before.$$
  diff /tmp/0028-before.$$ "$PI" || true
  rm -f /tmp/0028-before.$$
  exit 1
fi
grep -qE '^\.claude/hooks/?$' "$PI" && { echo "STEP1 failed: redundant .claude/hooks/ entry appended"; exit 1; }
grep -q '^# AgenticApps workflow (0028):' "$PI" && { echo "STEP1 failed: rollback marker written on a no-op"; exit 1; }

# Existing content preserved untouched.
for line in 'dist/' 'coverage/' '.claude' 'docs/generated/'; do
  grep -qF "$line" "$PI" || { echo "STEP1 not surgical: pre-existing '$line' dropped"; exit 1; }
done

# Step 2: the version bump still happens — the no-op is Step 1's alone.
grep -q '^version: 2\.6\.0$' "$SKILL" || { echo "STEP2 failed: version not bumped to 2.6.0"; exit 1; }

# ── Idempotency: re-apply changes nothing ────────────────────────────────────
before_pi2="$(cat "$PI")"; before_skill="$(cat "$SKILL")"
apply_step1 >/dev/null 2>&1; apply_step2
[ "$before_pi2" = "$(cat "$PI")" ] || { echo "STEP1 not idempotent: re-apply changed .prettierignore"; exit 1; }
[ "$before_skill" = "$(cat "$SKILL")" ] || { echo "STEP2 not idempotent: re-apply changed SKILL.md"; exit 1; }

echo "OK: 0028 treats a subsuming bare '.claude' as already-applied; no redundant entry; version bumped"
exit 0
