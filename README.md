# AgenticApps Claude Workflow

A portable Claude Code workflow that integrates **Superpowers + GSD + gstack** into a
disciplined spec-first development pipeline with enforced hooks.

## What this gives you

- **Pre-phase brainstorming** before any code is written (UI alternatives, architecture decisions)
- **Strict TDD enforcement** (red-green-refactor, not code-first)
- **UI preview verification** before committing frontend changes
- **Automatic post-phase gates**: `/review`, `/cso`, `/qa` run after every phase
- **Session handoff** for context preservation across sessions
- **Supabase connection patterns** (direct vs pooler, auth flow, .env setup)

## Prerequisites

Install these globally first:

```bash
# Superpowers plugin
claude plugins install superpowers

# GSD (Get Shit Done)
# Follow: https://github.com/get-shit-done/gsd

# gstack
# Follow: https://github.com/garrytan/gstack
```

## Installation

### Option A: Global install (applies to all repos)

```bash
# Clone to your global skills directory
git clone https://github.com/agenticapps-eu/claude-workflow.git ~/.claude/skills/agenticapps-workflow

# Copy the global CLAUDE.md additions
cat ~/.claude/skills/agenticapps-workflow/global-claude-additions.md >> ~/.claude/CLAUDE.md
```

### Option B: Per-project install

```bash
# From your project root
mkdir -p .claude/skills
git clone https://github.com/agenticapps-eu/claude-workflow.git .claude/skills/agenticapps-workflow

# Run the setup command
claude "/setup-agenticapps-workflow"
```

### Option C: Setup a new project from scratch

```bash
# From your project root
claude "/setup-agenticapps-workflow"
```

This will:
1. Copy the skill to `.claude/skills/agentic-apps-workflow/`
2. Create `.claude/workflow-config.md` with your project details
3. Add hooks config to `.planning/config.json`
4. Add workflow enforcement rules to your project's `CLAUDE.md`

## What gets installed

```
.claude/
  skills/
    agentic-apps-workflow/
      SKILL.md              # The workflow skill (triggers on any code task)
  workflow-config.md        # Project-specific settings + hook definitions

.planning/
  config.json               # GSD config with hooks section

CLAUDE.md additions:
  - Development Workflow section
  - Superpowers Integration Hooks (MANDATORY) section
  - Session handoff instructions
```

## Hook execution order

```
/gsd-execute-phase {N}
  |
  +-- PRE-PHASE HOOKS
  |   +-- brainstorm_ui (if UI plans exist)
  |   +-- brainstorm_architecture (if arch plans exist)
  |
  +-- WAVE EXECUTION (GSD executor agents)
  |   +-- per-plan: tdd_enforcement, ui_preview
  |
  +-- POST-PHASE HOOKS (before verifier)
  |   +-- /review (always)
  |   +-- /cso (if auth/storage/api/llm scope)
  |   +-- /qa (if dev server running)
  |
  +-- PHASE VERIFICATION (GSD verifier agent)
```

## Customization

Edit `.claude/workflow-config.md` to adjust:
- Which hooks are active
- CSO trigger scopes
- QA behavior (auto vs manual)
- TDD strictness

Edit `.planning/config.json` → `hooks` to toggle individual hooks on/off.
