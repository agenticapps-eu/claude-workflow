#!/bin/sh
# Sourced by each migration-0018 fixture's setup.sh. Builds a v1.16.0 GSD
# project skeleton in the sandbox CWD:
#   - .claude/skills/agentic-apps-workflow/SKILL.md at version 1.16.0 (0018's
#     pre-flight requires 1.16.0)
#   - .planning/config.json — the installed copy of config-hooks.json (baseline
#     0000 installs config-hooks.json as .planning/config.json), with a
#     post_phase block that does NOT yet contain observability_scan
#   - .claude/hooks/ (empty — the hook is not installed yet)
# Each fixture's setup.sh customises this baseline (fresh vs already-applied).
set -eu

mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 1.16.0
implements_spec: 0.4.0
description: synthetic test fixture for migration 0018
---
EOF_PROJ_SKILL

mkdir -p .planning .claude/hooks
cat > .planning/config.json <<'EOF_CONFIG'
{
  "hooks": {
    "post_phase": {
      "spec_review": { "enabled": true, "skill": "gstack:review" },
      "qa": { "enabled": true, "skill": "gstack:qa" }
    }
  }
}
EOF_CONFIG
