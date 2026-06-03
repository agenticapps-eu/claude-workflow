#!/bin/sh
# Sourced by individual fixture setup.sh scripts for migration 0022.
# Builds a sandboxed project (BEFORE state) at workflow v1.20.0 with:
#   - an `observability:` metadata block in CLAUDE.md still naming the
#     OLD `skill: add-observability` (the repoint target for Step 1),
#   - a prompt-type Haiku Stop hook in .claude/settings.json (the #58
#     hook the migration's Step 3 swaps),
#   - a project-local hyphenated SKILL.md at version 1.20.0 (Step 4's
#     version-bump target).
# It does NOT, by itself, place the `observability` skill in $HOME — each
# fixture's setup.sh decides whether to install it (present vs absent),
# because the obs-skill presence is the pre-flight gate under test.
set -eu

# 1. Project-local hyphenated SKILL.md at v1.20.0 (Step 4 bumps this exact path).
mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 1.20.0
implements_spec: 0.4.0
description: synthetic test fixture for migration 0022
---
EOF_PROJ_SKILL

# 2. CLAUDE.md with an observability: block still naming add-observability
#    (Step 1 repoints `skill: add-observability` -> `skill: observability`).
cat > CLAUDE.md <<'EOF_CLAUDE'
# Test fixture CLAUDE.md (migration 0022)

observability:
  spec_version: 0.4.0
  skill: add-observability
  policy: lib/observability/policy.md
EOF_CLAUDE

# 3. .claude/settings.json with the prompt-type Haiku Stop hook (Hook 3) the
#    migration's Step 3 swaps for the deterministic type:command phase-sentinel.sh.
mkdir -p .claude
cat > .claude/settings.json <<'EOF_SETTINGS'
{
  "hooks": {
    "PreToolUse": [
      {
        "_hook": "Hook 1 — Database Sentinel",
        "matcher": "Bash|Edit|Write",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/database-sentinel.sh", "timeout": 5000 }
        ]
      }
    ],
    "Stop": [
      {
        "_hook": "Hook 3 — Phase Sentinel (Haiku, prompt-type)",
        "hooks": [
          {
            "type": "prompt",
            "model": "claude-haiku-4-5-20251001",
            "timeout": 30000,
            "prompt": "Read $CLAUDE_PROJECT_DIR/.planning/current-phase/checklist.md if it exists. Return {\"ok\": true} or {\"ok\": false}."
          }
        ]
      }
    ]
  }
}
EOF_SETTINGS

# 4. install the `observability` skill into the sandbox $HOME unless the
#    caller opted out (OBS_SKILL_ABSENT=1). This models the pre-flight gate:
#    present -> migration may apply; absent -> pre-flight aborts (exit 3).
if [ "${OBS_SKILL_ABSENT:-0}" != "1" ]; then
  mkdir -p "$HOME/.claude/skills/observability"
  cat > "$HOME/.claude/skills/observability/SKILL.md" <<'EOF_OBS_SKILL'
---
name: observability
version: 0.11.1
implements_spec: 0.3.2
---
EOF_OBS_SKILL
fi
