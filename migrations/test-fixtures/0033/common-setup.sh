#!/usr/bin/env bash
# common-setup.sh — build a sandboxed 3.0.0 project for migration 0033.
#
# Sourced (not executed) by each fixture's setup.sh so a fixture can vary one
# thing. Knobs:
#   WITH_WORKFLOW_MD=0      omit .claude/claude-md/workflow.md   (03-absent-noop)
#   WITH_CONFIG_MD=0        omit .claude/workflow-config.md      (03-absent-noop)
#   WITH_TRAILING_SECTION=1 add a project-owned `## ` section AFTER the hooks
#                           section of workflow-config.md        (04)
#
# The vendored documents below are deliberately hand-written stubs of the
# PRE-0033 shape, not `git show HEAD:...` extracts: once this change is
# committed, HEAD carries the retargeted payload and a git-derived fixture would
# quietly start testing the after-state against itself.
set -euo pipefail

: "${WITH_WORKFLOW_MD:=1}"
: "${WITH_CONFIG_MD:=1}"
: "${WITH_TRAILING_SECTION:=0}"

git init -q .
git config user.email t@t.t
git config user.name t

mkdir -p .claude/claude-md .claude/skills/agentic-apps-workflow .planning

# --- the scaffolder clone the migration reads from -------------------------
# 0033 resolves it at ~/.claude/skills/agenticapps-workflow; HOME is faked.
mkdir -p "$HOME/.claude/skills"
ln -sfn "$REPO_ROOT" "$HOME/.claude/skills/agenticapps-workflow"

# --- the installed workflow skill at the 3.0.0 floor ------------------------
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_SKILL'
---
name: agentic-apps-workflow
version: 3.0.0
implements_spec: 1.0.0
---
# stub
EOF_SKILL

# --- the pre-0033 vendored workflow reference (GSD-teaching) ----------------
if [ "$WITH_WORKFLOW_MD" = "1" ]; then
  cat > .claude/claude-md/workflow.md <<'EOF_WF'
<!-- vendored-from: claude-workflow templates/.claude/claude-md/workflow.md -->

# AgenticApps Workflow — Superpowers + GSD + gstack

## Development Workflow

1. Check GSD state → understand current task
6. Update GSD state

**The flags in `.planning/config.json` → `hooks` declare intent but NO GSD
workflow code reads them.**

### Pre-Phase Hooks (before `/gsd-execute-phase`)

1. **Brainstorm UI plans + design critique** — stub.

### 13 Red Flags — Trigger Automatic STOP → DELETE → RESTART

1. Code written before the test (for `tdd="true"` tasks)
6. Any "just this once" reasoning
12. Describing discipline as "dogmatic" or "slowing us down"
13. Any "This case is different because..." opener

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command.

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
EOF_WF
fi

# --- the pre-0033 project config, WITH placeholders already substituted -----
# The substituted values are the point of fixture 01: a byte-copy of the
# template would put {{PROJECT_NAME}} and friends back.
if [ "$WITH_CONFIG_MD" = "1" ]; then
  cat > .claude/workflow-config.md <<'EOF_CFG'
# Workflow Configuration

## Project
- **Name**: sandbox-repo
- **Repo**: github.com/example/sandbox-repo
- **Client**: Example Client
- **Budget**: 40h

## Tech Stack
- **Backend**: Go
- **Frontend**: React
- **Database**: Postgres
- **LLM**: claude

## Superpowers Integration Hooks

These hooks enforce the Superpowers + GSD + gstack workflow.
They are read from `.planning/config.json` → `hooks` and enforced via CLAUDE.md rules.

### Pre-Phase (orchestrator runs before spawning executors)

| Hook | Trigger | Skill | What it does |
|------|---------|-------|-------------|
| `brainstorm_ui` | Plan has frontend files | `superpowers:brainstorming` | stub |

### Hook execution order

```
/gsd-execute-phase {N}
  │
  └── PHASE VERIFICATION (GSD verifier agent)
```
EOF_CFG

  if [ "$WITH_TRAILING_SECTION" = "1" ]; then
    cat >> .claude/workflow-config.md <<'EOF_EXTRA'

## Project-owned appendix

This section was added by the project AFTER the vendored hooks section and
MUST survive the re-vendor verbatim.
EOF_EXTRA
  fi
fi

# state that 0033 must not touch
mkdir -p .planning/phases/01-example
printf '# example phase\n' > .planning/phases/01-example/PLAN.md
