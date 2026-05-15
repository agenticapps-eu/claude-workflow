#!/bin/sh
# Fixture 05 — post-rollback state. Migration was applied (symlink created,
# version bumped), then rolled back per the procedure: rm the symlink (if
# pointing at scaffolder) + revert version 1.11.0 → 1.10.0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Step A: simulate full apply
ln -sfn "$HOME/.claude/skills/agenticapps-workflow/add-observability" \
        "$HOME/.claude/skills/add-observability"
sed -i.bak 's/^version: 1\.10\.0$/version: 1.11.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak

# Step B: apply the rollback procedure exactly as documented in 0012:
# - Step 1 rollback: remove symlink only if it points at the scaffolder
if [ -L "$HOME/.claude/skills/add-observability" ] && \
   readlink "$HOME/.claude/skills/add-observability" | grep -q '/agenticapps-workflow/add-observability$'; then
  rm "$HOME/.claude/skills/add-observability"
fi
# - Step 3 rollback: revert version
sed -i.bak 's/^version: 1\.11\.0$/version: 1.10.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
