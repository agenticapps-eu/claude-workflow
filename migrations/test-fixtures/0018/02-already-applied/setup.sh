#!/bin/sh
# Fixture 02 — already-applied state: reproduce migration 0018's three Apply
# steps using the scaffolder sources in $REPO_ROOT, so verify.sh can confirm
# every idempotency check now returns "applied" (no-op on re-run).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Step 1 — install the hook script (source: scaffolder template in REPO_ROOT).
cp "$REPO_ROOT/templates/.claude/hooks/observability-postphase-scan.sh" \
   .claude/hooks/observability-postphase-scan.sh
chmod +x .claude/hooks/observability-postphase-scan.sh

# Step 2 — wire observability_scan into .planning/config.json post_phase.
ENTRY=$(jq '.hooks.post_phase.observability_scan' "$REPO_ROOT/templates/config-hooks.json")
jq --argjson entry "$ENTRY" '
  .hooks //= {} | .hooks.post_phase //= {} |
  .hooks.post_phase.observability_scan = $entry
' .planning/config.json > .planning/config.json.tmp && mv .planning/config.json.tmp .planning/config.json

# Step 3 — bump installed version 1.16.0 → 1.17.0.
sed 's/^version: 1\.16\.0$/version: 1.17.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md > .claude/skills/agentic-apps-workflow/SKILL.md.tmp \
  && mv .claude/skills/agentic-apps-workflow/SKILL.md.tmp .claude/skills/agentic-apps-workflow/SKILL.md
