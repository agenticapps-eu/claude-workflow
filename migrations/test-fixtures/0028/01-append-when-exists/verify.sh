#!/bin/sh
# Verify migration 0028 against a project that HAS a .prettierignore lacking the
# .claude/hooks entry: Step 1 appends it (preserving existing content), Step 2
# bumps the version, and both steps are idempotent on re-apply.
set -eu

PI=.prettierignore
SKILL=.claude/skills/agentic-apps-workflow/SKILL.md

# Pre-condition: the fixture's .prettierignore exists without the entry.
[ -f "$PI" ] || { echo "PRE: fixture must have a .prettierignore"; exit 1; }
grep -qE '^\.claude/hooks/?$' "$PI" && { echo "PRE: entry must be absent before apply"; exit 1; }

# ── Step 1 apply — extracted from the migration doc, not copied here ─────────
. "$REPO_ROOT/migrations/test-fixtures/0028/common-verify.sh"
# ── Step 2 apply — version bump ──────────────────────────────────────────────
apply_step2() {
  sed 's/^version: 2\.5\.0$/version: 2.6.0/' "$SKILL" > "$SKILL.t" && mv "$SKILL.t" "$SKILL"
}

apply_step1
apply_step2

# Step 1: entry present exactly once.
grep -qE '^\.claude/hooks/?$' "$PI" || { echo "STEP1 failed: entry not appended"; exit 1; }
n=$(grep -cE '^\.claude/hooks/?$' "$PI")
[ "$n" -eq 1 ] || { echo "STEP1 failed: entry appears $n times, expected 1"; exit 1; }
# Marker comment present (rollback anchor).
grep -q '^# AgenticApps workflow (0028):' "$PI" || { echo "STEP1 failed: rollback marker missing"; exit 1; }
# Existing content preserved.
for line in 'dist/' 'coverage/' 'docs/generated/'; do
  grep -qF "$line" "$PI" || { echo "STEP1 not surgical: pre-existing '$line' dropped"; exit 1; }
done

# Step 2: version bumped.
grep -q '^version: 2\.6\.0$' "$SKILL" || { echo "STEP2 failed: version not bumped to 2.6.0"; exit 1; }

# ── Idempotency: re-apply changes nothing ────────────────────────────────────
before_pi="$(cat "$PI")"; before_skill="$(cat "$SKILL")"
apply_step1; apply_step2
[ "$before_pi" = "$(cat "$PI")" ] || { echo "STEP1 not idempotent: re-apply changed .prettierignore"; exit 1; }
[ "$before_skill" = "$(cat "$SKILL")" ] || { echo "STEP2 not idempotent: re-apply changed SKILL.md"; exit 1; }

echo "OK: 0028 appends .claude/hooks/ to an existing .prettierignore, surgically, idempotently; version bumped"
exit 0
