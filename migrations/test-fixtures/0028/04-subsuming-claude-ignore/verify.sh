#!/bin/sh
# Verify migration 0028 against a project whose .prettierignore already ignores
# the whole .claude directory. That entry subsumes .claude/hooks/, so Step 1
# must recognise the work as already done and append NOTHING. Appending a
# redundant .claude/hooks/ under a bare .claude adds noise to a project file
# for no formatting effect.
#
# Unlike fixtures 01-03, this one does not inline a copy of the migration's
# shell — it EXTRACTS Step 1's Apply block from the migration document and runs
# that. The inlined copies in 01-03 can drift from the document silently; here
# the document is the thing under test, so a predicate fix has to land in the
# document to make this fixture pass.
set -eu

PI=.prettierignore
SKILL=.claude/skills/agentic-apps-workflow/SKILL.md
MIGRATION="$REPO_ROOT/migrations/0028-register-prettierignore.md"

[ -f "$MIGRATION" ] || { echo "PRE: migration doc not found at $MIGRATION"; exit 1; }

# Pre-condition: a .prettierignore with a bare `.claude` and no `.claude/hooks`.
[ -f "$PI" ] || { echo "PRE: fixture must have a .prettierignore"; exit 1; }
grep -qE '^\.claude$' "$PI" || { echo "PRE: fixture must ignore bare .claude"; exit 1; }
grep -qE '^\.claude/hooks/?$' "$PI" && { echo "PRE: .claude/hooks must be absent before apply"; exit 1; }

# ── Extract Step 1's Apply block from the migration document ────────────────
extract_step1_apply() {
  awk '
    /^### Step 1/ { in1=1; next }
    /^### Step 2/ { in1=0 }
    in1 && /^\*\*Apply:\*\*/ { want=1; next }
    want && /^```bash$/ { inb=1; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$1"
}

STEP1_APPLY="$(extract_step1_apply "$MIGRATION")"
[ -n "$STEP1_APPLY" ] || { echo "PRE: could not extract Step 1 Apply block from the migration"; exit 1; }

apply_step1() { eval "$STEP1_APPLY"; }
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
