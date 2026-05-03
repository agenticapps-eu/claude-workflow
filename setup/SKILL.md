---
name: setup-agenticapps-workflow
description: |
  Bootstrap a fresh project with the AgenticApps Superpowers + GSD + gstack
  workflow. Applies all migrations from `0000-baseline.md` forward to the
  current scaffolder version. Use when the user runs
  "/setup-agenticapps-workflow", "set up the workflow", "install agenticapps
  workflow", or "scaffold this project". Handles project file creation,
  CLAUDE.md additions, hooks config, and version recording. Eliminates the
  divergent code paths between setup and update by routing both through the
  same migration framework.
---

# Setup AgenticApps Workflow

Bootstrap a project from zero to the latest AgenticApps workflow version by
applying every migration from `0000-baseline.md` forward.

This skill **shares the migration runtime** with `update-agenticapps-workflow`.
The only difference: setup starts from `from_version: unknown` (a fresh
project with no installed workflow), update starts from a detected installed
version.

There is **no parallel code path**. Setup and update both read the same
migration files, run the same idempotency checks, and produce the same
on-disk shape. This eliminates the historical "setup writes one config,
update writes a different one" drift that plagued the v1.2.0 setup process.

## Step 0: Parse flags

Recognize these optional flags:

| Flag | Effect |
|---|---|
| `--dry-run` | Show every step's diff without writing or committing. |
| `--target-version V` | Stop applying migrations after `to_version V` (advanced — for installing a specific historical version, e.g. for reproducing an old project). Default: latest. |

## Step 1: Pre-flight

```bash
# Project root must be a git repo
test -d .git || {
  echo "ERROR: not a git repo. Run 'git init' first, then re-run this skill."
  exit 1
}

# Refuse if already installed
if [ -f .claude/skills/agentic-apps-workflow/SKILL.md ]; then
  INSTALLED=$(awk '/^---$/{f++; next} f==1 && /^version:/ {print $2; exit}' .claude/skills/agentic-apps-workflow/SKILL.md)
  echo "ERROR: AgenticApps workflow already installed (version $INSTALLED)."
  echo "Use /update-agenticapps-workflow to upgrade, or remove .claude/skills/agentic-apps-workflow/ first."
  exit 1
fi

# Workflow scaffolder must be present (this skill reads from it)
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
test -d "$SCAFFOLDER" || {
  echo "ERROR: workflow scaffolder not found at $SCAFFOLDER."
  echo "Install it: git clone https://github.com/agenticapps-eu/claude-workflow.git $SCAFFOLDER"
  exit 1
}

# External tools (carried over from prior setup behavior — these were
# checked at setup time before the migration framework existed)
command -v claude >/dev/null 2>&1 || echo "WARN: claude CLI not on PATH"
ls ~/.claude/get-shit-done/bin/gsd-tools.cjs >/dev/null 2>&1 || echo "WARN: GSD not installed"
ls ~/.claude/skills/gstack/VERSION >/dev/null 2>&1 || echo "WARN: gstack not installed"
ls ~/.claude/plugins/cache/claude-plugins-official/superpowers/ >/dev/null 2>&1 || echo "WARN: superpowers plugin not installed"
```

Warnings (rather than errors) on the optional tooling preserve the prior
behavior: a project can be set up without GSD or gstack present, and they
can be added later.

## Step 2: Choose install scope (Option A vs B vs C from README)

Use AskUserQuestion:

> How should this workflow be installed?
> A) Per-project (project-local): the workflow is scoped to this repo only. Best for client repos.  [Recommended]
> B) Global (~/.claude/CLAUDE.md additions): the workflow applies across all your projects. Best for personal repos.
> C) Both: per-project install AND append to global CLAUDE.md.

Record the choice as `$SCOPE` (one of `per-project`, `global`, `both`).
This drives whether migration `0000-baseline.md` Step 5 (append global
CLAUDE.md additions) runs.

## Step 3: Discover all migrations

```bash
MIGRATIONS_DIR="$SCAFFOLDER/migrations"
test -d "$MIGRATIONS_DIR" || { echo "ERROR: $MIGRATIONS_DIR missing"; exit 1; }

# Find every migration in order, sorted by ID
ls "$MIGRATIONS_DIR"/[0-9]*.md | sort
```

Apply migrations in sequential ID order, starting from `0000-baseline.md`.
If `--target-version V` was passed, stop after the migration whose
`to_version` matches `V`.

## Step 4: Gather project details (for 0000 placeholder substitution)

Migration 0000 Step 2 substitutes placeholders in `workflow-config.md`.
Gather the values up-front via AskUserQuestion (one prompt per non-derivable
placeholder; derivable ones are auto-filled):

| Placeholder | Source |
|---|---|
| `{{PROJECT_NAME}}` | AskUserQuestion: "Project name?" (default: `basename $(pwd)`) |
| `{{REPO}}` | Auto: `git remote get-url origin 2>/dev/null` (else AskUserQuestion) |
| `{{CLIENT}}` | AskUserQuestion: "Client (or 'internal')?" |
| `{{BUDGET}}` | AskUserQuestion: "Budget tier?" Options: free / paid / enterprise |
| `{{BACKEND}}` | AskUserQuestion: "Primary backend language?" Options: Go / Node / Python / Ruby / Other |
| `{{FRONTEND}}` | AskUserQuestion: "Primary frontend stack?" Options: React / Vue / Svelte / None / Other |
| `{{DATABASE}}` | AskUserQuestion: "Primary database?" Options: Postgres / Supabase / MongoDB / Firebase / None / Other |
| `{{LLM}}` | AskUserQuestion: "Primary LLM?" Options: Anthropic / OpenAI / Both / None / Other |

Cache responses for use during Step 5.

## Step 5: Apply each migration in order

For each migration in the chain (starting with `0000-baseline.md`):

Delegate to the same per-migration logic that `update-agenticapps-workflow`
uses (see `update/SKILL.md` Step 5). The interface is identical:

1. Run **Pre-flight** (the migration's pre-flight shell block).
2. For each **Step**:
   - Idempotency check (skip if already applied)
   - Pre-condition check (abort if missing prerequisite)
   - Show diff (or apply, depending on `--dry-run`)
   - For migration `0000-baseline.md` Step 2 (workflow-config substitution),
     use the cached responses from Step 4 above instead of re-prompting.
   - For migration `0000-baseline.md` Step 5 (global CLAUDE.md append):
     skip if `$SCOPE = per-project`; apply if `$SCOPE` is `global` or `both`.
3. Run **Post-checks**.
4. Bump the version field in
   `.claude/skills/agentic-apps-workflow/SKILL.md` to the migration's
   `to_version`.
5. Commit atomically:
   ```bash
   git add -A
   git commit -m "chore: setup AgenticApps workflow — migration {ID} (v{TO_VERSION})"
   ```

If `--dry-run`, no writes and no commits — just diffs.

## Step 6: Post-setup summary

```
Setup complete.

Workflow installed at version: {LATEST_VERSION}
Migrations applied:
  ✅ 0000 (unknown → 1.2.0): Baseline
  ✅ 0001 (1.2.0 → 1.3.0): Go skills + impeccable + database-sentinel
  ...

Files created / modified:
  - .claude/skills/agentic-apps-workflow/SKILL.md  (workflow skill)
  - .claude/workflow-config.md                     (project config)
  - .planning/config.json                          (hooks)
  - CLAUDE.md                                      (workflow rules appended)
  - templates/adr-db-security-acceptance.md        (ADR template, from 0001)
  {if scope was global or both:}
  - ~/.claude/CLAUDE.md                            (global additions appended)

Optional next steps:
  - Install per-language skill packs if applicable (Go: see README §Per-language skill packs).
  - Run /agenticapps-workflow to start your first phase.
  - Bookmark: future updates run via /update-agenticapps-workflow.
```

## Failure modes

| Failure | Behavior |
|---|---|
| Not a git repo | Error in Step 1; suggest `git init`; exit 1 |
| Already installed | Error in Step 1; suggest `/update-agenticapps-workflow`; exit 1 |
| Workflow scaffolder missing | Error in Step 1; suggest install command; exit 1 |
| Migration 0000 pre-condition fails (e.g. permissions) | Stop with the failing pre-condition; do not commit a partial setup |
| Mid-chain migration fails | The applied migrations have already been committed (one commit each). The user can resume by running `/update-agenticapps-workflow` once the failure is fixed. |

## Idempotency guarantee

Running setup twice produces an error in Step 1 (refuses if already
installed). To re-run setup safely, the user must explicitly remove
`.claude/skills/agentic-apps-workflow/` first (which is documented as a
destructive operation in the error message).

This is intentional — setup is a one-time bootstrap. Idempotent re-execution
is the job of `/update-agenticapps-workflow`.

## Migration history (for reference)

The migration sequence applied by setup is:

| ID | from → to | Title |
|---|---|---|
| 0000 | unknown → 1.2.0 | Baseline (workflow files, hooks, CLAUDE.md sections) |
| 0001 | 1.2.0 → 1.3.0 | Wire Go skill packs + impeccable + database-sentinel |
| ... | | (future migrations land here as they ship) |

A new project freshly setup gets ALL of these in sequence.

## Reference: related skills

- `update-agenticapps-workflow` — apply pending migrations to an
  already-installed workflow.
- `agentic-apps-workflow` — the workflow itself; this skill installs the
  project's local copy of it.

## Migration to this refactor

The previous (v1.2.0) version of this skill executed the setup steps inline,
without a migration framework. Projects set up under that version are
indistinguishable on disk from projects set up under this refactor (the
end-state is the same). The migration framework only changes the
**procedure** that produces that end-state — and unlocks non-destructive
upgrades for the next set of features.
