#!/bin/sh
# Fixture 02 — idempotent re-apply (after-state). All 3 steps already
# applied. Re-running the migration reports "skipped (already applied)"
# for each step.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Simulate post-apply state:
# - Symlink at $HOME/.claude/skills/add-observability → scaffolder's add-observability
ln -sfn "$HOME/.claude/skills/agenticapps-workflow/add-observability" \
        "$HOME/.claude/skills/add-observability"
# - Workflow version bumped to 1.11.0
sed -i.bak 's/^version: 1\.10\.0$/version: 1.11.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
