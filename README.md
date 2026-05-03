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
- **Pre-phase design critique** — `impeccable:critique` scores each
  `/design-shotgun` variant against ~24 AI-slop anti-patterns; sub-bar
  variants are eliminated before the user picks. Recorded in UI-SPEC.md.
- **Strict TDD enforcement** via `superpowers:test-driven-development`
  (red-green-refactor with atomic commit pair per task, not code-first).
- **UI preview verification** — dev server + `/browse` screenshot required before commit.
- **Verification-before-completion** — `superpowers:verification-before-completion`
  gate before any task is marked done. Evidence before assertions, always.
- **Two-stage review** — gstack `/review` (spec compliance) then
  `superpowers:requesting-code-review` (code quality) with independent reviewer.
  The two stages do not collapse.
- **Language-aware Stage 2** — Go phases run `samber:cc-skills-golang` +
  `netresearch:go-development-skill` (resilience pack); TS/React phases run
  `QuantumLynx:ts-react-linter-driven-development`. Routing is auto.
- **Automatic post-phase gates**: `/review`, `/cso`, `/qa` after every phase.
- **Database security sub-gate** — `database-sentinel:audit` runs as a
  sub-gate under `/cso` whenever the phase touches Supabase / Postgres /
  MongoDB. Critical / High findings BLOCK branch close unless accepted via
  `templates/adr-db-security-acceptance.md`.
- **Finishing-stage audits** — `impeccable:audit` for frontend changes;
  `database-sentinel:audit` (full-surface) for pre-launch.
- **Commitment ritual** — the workflow skill emits a public commitment block
  listing the skills it will invoke before touching any code, leveraging the
  Cialdini consistency principle.
- **Versioned migration framework** — existing projects upgrade
  non-destructively via `/update-agenticapps-workflow`. Setup and update
  share one runtime (no divergent code paths). See
  [Updating an existing project](#updating-an-existing-project) below.
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

In your project (per Option B / C above):

```
.claude/
  skills/
    agentic-apps-workflow/
      SKILL.md              # The workflow skill (triggers on any code task)
  workflow-config.md        # Project-specific settings + hook definitions

.planning/
  config.json               # GSD config with hooks section (incl. impeccable +
                            # database-sentinel sub-gates)

templates/
  adr-db-security-acceptance.md  # ADR template for Critical/High DB findings

CLAUDE.md additions:
  - Development Workflow section
  - Superpowers Integration Hooks (MANDATORY) section (Hook 1 includes
    impeccable critique; Hook 8 includes database-sentinel sub-gate)
  - Session handoff instructions
```

The scaffolder repo itself (cloned globally to
`~/.claude/skills/agenticapps-workflow/`) ships:

```
agenticapps-workflow/
  skill/SKILL.md            # The workflow skill (with `version: X.Y.Z` field)
  setup/SKILL.md            # /setup-agenticapps-workflow — applies migrations
                            # from baseline forward
  update/SKILL.md           # /update-agenticapps-workflow — applies pending
                            # migrations to an installed project
  migrations/               # Versioned migration files
    README.md               # Format spec
    0000-baseline.md        # v1.2.0 starting state
    0001-go-impeccable-database-sentinel.md  # v1.2.0 → v1.3.0
    test-fixtures/          # Test harness contract
    run-tests.sh            # Migration test runner
  templates/                # Files copied into projects during setup
  docs/                     # ENFORCEMENT-PLAN.md + ADRs
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

## Updating an existing project

When the workflow scaffolder ships a new version, upgrade your project
non-destructively by applying pending migrations:

```bash
cd <your-project>

# Make sure the scaffolder is fresh
cd ~/.claude/skills/agenticapps-workflow && git pull && cd -

# Preview what would change (recommended first)
claude "/update-agenticapps-workflow --dry-run"

# Apply (interactive — confirms each migration step)
claude "/update-agenticapps-workflow"
```

The `update-agenticapps-workflow` skill:

1. Detects your project's installed version from
   `.claude/skills/agentic-apps-workflow/SKILL.md` frontmatter.
2. Finds pending migrations in
   `~/.claude/skills/agenticapps-workflow/migrations/` (only those whose
   `from_version ≤ installed < to_version` are pending).
3. Pre-flights required external skills (e.g. impeccable, database-sentinel)
   and prompts you to install any missing ones — does NOT auto-install.
4. Shows each step's diff and asks for per-step confirm. Idempotent —
   already-applied steps are skipped.
5. Bumps your project's installed-version field to each migration's
   `to_version` after the migration's post-checks pass.
6. Commits atomically with `chore: migrate AgenticApps workflow to v{X.Y.Z}`.

**Flags:**
- `--dry-run` — show all diffs without writing or committing
- `--migration N` — apply only migration `NNNN` (advanced, for retry)
- `--from V` — override the detected installed version (advanced)

Migrations live in `~/.claude/skills/agenticapps-workflow/migrations/`.
See `migrations/README.md` for the file format and the "Adding a new
migration" checklist if you're contributing a new migration upstream.

## Customization

Edit `.claude/workflow-config.md` to adjust:
- Which hooks are active
- CSO trigger scopes
- QA behavior (auto vs manual)
- TDD strictness

Edit `.planning/config.json` → `hooks` to toggle individual hooks on/off.
