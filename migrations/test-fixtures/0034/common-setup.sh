#!/usr/bin/env bash
# common-setup.sh — build a sandboxed 3.1.0 project for migration 0034.
#
# Knobs:
#   WITH_WORKFLOW_MD=0   omit .claude/claude-md/workflow.md   (03-absent-file-noop)
#
# The vendored document below is a hand-written stub of the POST-0033 /
# PRE-0034 shape: retargeted onto OpenSpec (so it carries no GSD references)
# but still restating the SKILL's rule blocks, which is exactly what 0034
# removes. Not a `git show HEAD:...` extract — once this change is committed,
# HEAD carries the companion and a git-derived fixture would test the
# after-state against itself.
set -euo pipefail

: "${WITH_WORKFLOW_MD:=1}"

git init -q .
git config user.email t@t.t
git config user.name t

mkdir -p .claude/claude-md .claude/skills/agentic-apps-workflow

# --- the scaffolder clone the migration reads from -------------------------
mkdir -p "$HOME/.claude/skills"
ln -sfn "$REPO_ROOT" "$HOME/.claude/skills/agenticapps-workflow"

# --- the installed workflow skill at the 3.1.0 floor ------------------------
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_SKILL'
---
name: agentic-apps-workflow
version: 3.1.0
implements_spec: 1.0.0
---
# stub
EOF_SKILL

# --- CLAUDE.md linking to the vendored file (0034 must not touch it) --------
cat > CLAUDE.md <<'EOF_CMD'
# Project

## Workflow

Full hooks, rituals, and red-flag tables: [`.claude/claude-md/workflow.md`](.claude/claude-md/workflow.md).
EOF_CMD

# --- the post-0033 vendored copy: correct, but a duplicate ------------------
if [ "$WITH_WORKFLOW_MD" = "1" ]; then
  cat > .claude/claude-md/workflow.md <<'EOF_WF'
<!-- vendored-from: claude-workflow templates/.claude/claude-md/workflow.md -->

# AgenticApps Workflow — OpenSpec + Superpowers + gstack

## The lifecycle (spec §17)

`openspec/changes/` are in-flight deltas.

## Superpowers Integration Hooks (MANDATORY — NON-NEGOTIABLE)

### The Commitment Ritual (emit FIRST, before any tool call)

```
## Workflow commitment

I am using the agentic-apps-workflow skill for this task.
```

### Rationalization Table (pattern-match your own reasoning)

| If you think... | The reality is... |
|---|---|
| "Simple change, skip brainstorming" | Simple changes produce most outages. |

## 14 Red Flags — STOP → DELETE → RESTART

1. Code written before the test (for TDD tasks)
14. Code written under an active change whose `REVIEWS.md` has < 2 reviewers
EOF_WF
fi
