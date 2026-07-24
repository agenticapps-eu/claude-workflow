#!/usr/bin/env bash
# common-setup.sh — build a sandboxed 2.9.0 project for migration 0032.
#
# Sourced (not executed) by each fixture's setup.sh so a fixture can vary one
# thing. Knobs:
#   WITH_GITNEXUS=0        omit the gitnexus hook/scripts/binding (04-no-gitnexus-noop)
#   WITH_OWN_PRECOMMIT=1   install a project-owned pre-commit hook first (03)
#   WITH_EXTRA_HOOKS=1     add unrelated Pre/PostToolUse entries that must survive (05)
set -euo pipefail

: "${WITH_GITNEXUS:=1}"
: "${WITH_OWN_PRECOMMIT:=0}"
: "${WITH_EXTRA_HOOKS:=0}"

git init -q .
git config user.email t@t.t
git config user.name t

mkdir -p .claude/hooks .claude/scripts .claude/skills/agentic-apps-workflow \
         .planning/phases/01-example

# --- the scaffolder clone the migration reads from -------------------------
# 0032 resolves it at ~/.claude/skills/agenticapps-workflow; HOME is faked.
mkdir -p "$HOME/.claude/skills"
ln -sfn "$REPO_ROOT" "$HOME/.claude/skills/agenticapps-workflow"

# --- the installed workflow skill at the 2.9.0 floor ------------------------
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_SKILL'
---
name: agentic-apps-workflow
version: 2.9.0
implements_spec: 0.9.0
---
# stub
EOF_SKILL

# --- 0.x-shaped .planning/config.json with a repo-specific §15 block --------
cat > .planning/config.json <<'EOF_CFG'
{
  "hooks": {
    "context_warnings": true,
    "pre_phase": { "design_critique": { "enabled": true, "trigger": "ui_hint_yes && ui_spec_exists" } },
    "pre_execute_gates": { "multi_ai_plan_review": { "enabled": true } },
    "post_phase": { "security": { "enabled": true, "sub_gates": [ { "skill": "database-sentinel:audit" } ] } },
    "finishing": { "impeccable_audit": { "enabled": true }, "db_pre_launch_audit": { "enabled": true } }
  },
  "knowledge_capture": {
    "enabled": true,
    "note": "~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/sandbox-repo.md"
  }
}
EOF_CFG

# --- the pre-3.0.0 hook payload --------------------------------------------
printf '#!/usr/bin/env bash\n# old PLAN.md-era gate\nexit 0\n' > .claude/hooks/multi-ai-review-gate.sh
chmod +x .claude/hooks/multi-ai-review-gate.sh

pre_extra=''
post_extra=''
if [ "$WITH_GITNEXUS" = "1" ]; then
  printf '#!/usr/bin/env node\n// reindex engine\n' > .claude/hooks/gitnexus-reindex.cjs
  chmod +x .claude/hooks/gitnexus-reindex.cjs
  printf '#!/usr/bin/env bash\nexit 0\n' > .claude/scripts/install-gitnexus.sh
  printf '#!/usr/bin/env bash\nexit 0\n' > .claude/scripts/rollback-gitnexus.sh
  printf '#!/usr/bin/env bash\nexit 0\n' > .claude/scripts/index-family-repos.sh
  chmod +x .claude/scripts/*.sh
  mkdir -p .gitnexus && printf '{}' > .gitnexus/meta.json
  post_extra=',{"_hook":"Hook — GitNexus background reindex (migration 0026)","matcher":"Bash","hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs","timeout":5000}]}'
fi
if [ "$WITH_EXTRA_HOOKS" = "1" ]; then
  pre_extra=',{"_hook":"Hook 1 — Database Sentinel","matcher":"Bash|Edit|Write","hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/database-sentinel.sh","timeout":5000}]}'
fi

cat > .claude/settings.json <<EOF_SET
{
  "hooks": {
    "PreToolUse": [
      {"_hook":"Hook 7 — Multi-AI Plan Review Gate (/gsd-review)","matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"\$CLAUDE_PROJECT_DIR/.claude/hooks/multi-ai-review-gate.sh","timeout":5000}]}${pre_extra}
    ],
    "PostToolUse": [
      {"_hook":"Hook 6 — Normalize CLAUDE.md","matcher":"Edit|Write|MultiEdit","hooks":[{"type":"command","command":"\$CLAUDE_PROJECT_DIR/.claude/hooks/normalize-claude-md.sh","timeout":5000}]}${post_extra}
    ]
  }
}
EOF_SET

if [ "$WITH_OWN_PRECOMMIT" = "1" ]; then
  printf '#!/usr/bin/env bash\n# the project OWNS this hook\necho project-precommit\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
fi

# a phase artifact that MUST survive (0032 never touches .planning/)
printf '# example phase\n' > .planning/phases/01-example/PLAN.md
