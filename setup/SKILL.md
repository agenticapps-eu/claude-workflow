---
name: setup-agenticapps-workflow
description: |
  Setup: Superpowers + GSD + gstack Workflow with enforced hooks.
  Copies the agentic-apps-workflow skill, creates workflow-config.md,
  adds hooks to config.json, and appends enforcement rules to CLAUDE.md.
  Use when the user says "setup workflow", "add agenticapps workflow",
  or wants to enable the Superpowers + GSD + gstack hooks for a project.
---

# Setup AgenticApps Workflow

This skill sets up the Superpowers + GSD + gstack workflow with enforced hooks
in the current project.

## Prerequisites Check

```bash
# Check required tools
command -v claude >/dev/null 2>&1 && echo "claude: OK" || echo "claude: MISSING"
ls ~/.claude/get-shit-done/bin/gsd-tools.cjs 2>/dev/null && echo "GSD: OK" || echo "GSD: MISSING"
ls ~/.claude/skills/gstack/VERSION 2>/dev/null && echo "gstack: OK" || echo "gstack: MISSING"
ls ~/.claude/plugins/cache/claude-plugins-official/superpowers/ 2>/dev/null && echo "superpowers: OK" || echo "superpowers: MISSING"
```

If any are MISSING, tell the user what to install and stop.

## Step 1: Copy the workflow skill

```bash
mkdir -p .claude/skills/agentic-apps-workflow
```

Read the SKILL.md from the installed skill location:
- Global: `~/.claude/skills/agenticapps-workflow/skill/SKILL.md`
- Or bundled: use the template content below

Copy to `.claude/skills/agentic-apps-workflow/SKILL.md`.

## Step 2: Create workflow-config.md

Use AskUserQuestion to gather project details:
- Project name
- Repo (org/name)
- Client (if any)
- Tech stack (backend, frontend, database, LLM)

Read the template from `~/.claude/skills/agenticapps-workflow/templates/workflow-config.md`
and substitute the values. Write to `.claude/workflow-config.md`.

## Step 3: Add hooks to config.json

Read `.planning/config.json`. If it exists, merge the hooks section from
`~/.claude/skills/agenticapps-workflow/templates/config-hooks.json`.
If it doesn't exist, create it with the hooks section.

## Step 4: Update CLAUDE.md

Read the project's `CLAUDE.md`. If it doesn't exist, create it.

Check if it already has a `## Development Workflow` section. If not, append
the sections from `~/.claude/skills/agenticapps-workflow/templates/claude-md-sections.md`.

Check if it already has `## Skill routing`. If not, append it.

## Step 5: Commit

```bash
git add .claude/skills/agentic-apps-workflow/ .claude/workflow-config.md .planning/config.json CLAUDE.md
git commit -m "chore: setup AgenticApps workflow (Superpowers + GSD + gstack hooks)"
```

## Step 6: Report

```
Workflow setup complete:
- .claude/skills/agentic-apps-workflow/SKILL.md — workflow trigger skill
- .claude/workflow-config.md — project config + hook definitions
- .planning/config.json — hooks config (pre/post/per-plan)
- CLAUDE.md — enforcement rules + skill routing

Pre-phase: brainstorm UI + architecture before execution
Per-plan: TDD enforcement + UI preview
Post-phase: /review + /cso + /qa automatically

Run `/gsd-execute-phase {N}` and the hooks will fire.
```
