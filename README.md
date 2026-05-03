# AgenticApps Claude Workflow

A portable Claude Code workflow that integrates **Superpowers + GSD + gstack** into a
disciplined spec-first development pipeline with enforced hooks.

## What this gives you

- **Enforcement contract** (`docs/ENFORCEMENT-PLAN.md`) mapping every GSD gate
  to its required Superpowers / gstack skill invocation, with rationalization
  table, 13 red flags, and pressure-test scenarios (Cialdini-style commitment).
- **Pre-phase brainstorming** before any code is written (`superpowers:brainstorming`
  for UI + architecture alternatives). UI phases additionally run gstack
  `/design-shotgun` to generate visual variants with live-server preview.
- **Strict TDD enforcement** via `superpowers:test-driven-development`
  (red-green-refactor with atomic commit pair per task, not code-first).
- **UI preview verification** — dev server + `/browse` screenshot required before commit.
- **Verification-before-completion** — `superpowers:verification-before-completion`
  gate before any task is marked done. Evidence before assertions, always.
- **Two-stage review** — gstack `/review` (spec compliance) then
  `superpowers:requesting-code-review` (code quality) with independent reviewer.
  The two stages do not collapse.
- **Automatic post-phase gates**: `/review`, `/cso`, `/qa` after every phase.
- **Commitment ritual** — the workflow skill emits a public commitment block
  listing the skills it will invoke before touching any code, leveraging the
  Cialdini consistency principle.
- **Session handoff** for context preservation across sessions.

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

## Per-language skill packs

Beyond the universal hooks, the workflow auto-routes language-specific skill packs
when a phase touches matching files. These packs are **project-local** installs —
only repos that need them pay the context cost.

### Go projects

```bash
# samber/cc-skills-golang (40+ Go skills with measured eval data)
cd <go-repo>
git clone https://github.com/samber/cc-skills-golang .claude/skills/cc-skills-golang
```

For `netresearch/go-development-skill` (production resilience patterns —
retry/backoff/graceful-shutdown/observability), install per the upstream pack's
own README. The action plan source documents an `npx @netresearch/skills add
go-development` invocation but it has not been independently verified in this
scaffolder; verify against the upstream README before relying on it.

Both packs compose: samber covers breadth + idioms, netresearch covers
production resilience. Routing is documented in
`templates/workflow-config.md` (Backend language routing section) and the
language-specific Stage 2 gates in `docs/ENFORCEMENT-PLAN.md`.

### TypeScript / React projects

`QuantumLynx:ts-react-linter-driven-development` is referenced in the routing
table but a verified install command is not yet documented in this repo. Track
in roadmap; until then, install per the upstream pack's own instructions.

### Python projects

No language pack adopted yet. Track in roadmap.

## Customization

Edit `.claude/workflow-config.md` to adjust:
- Which hooks are active
- CSO trigger scopes
- QA behavior (auto vs manual)
- TDD strictness

Edit `.planning/config.json` → `hooks` to toggle individual hooks on/off.
