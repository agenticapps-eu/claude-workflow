---
id: 0000
slug: baseline
title: AgenticApps workflow baseline (v1.2.0 starting state)
from_version: unknown
to_version: 1.2.0
applies_to:
  - .claude/skills/agentic-apps-workflow/SKILL.md
  - .claude/workflow-config.md
  - .planning/config.json
  - .claude/claude-md/workflow.md
  - CLAUDE.md
requires: []
optional_for: []
---

# Migration 0000 — Baseline (v1.2.0)

This is the **baseline migration**. Applied to a fresh project, it brings the
project to AgenticApps workflow v1.2.0 — the state the workflow ships before
any incremental migrations run.

`setup/SKILL.md` invokes this migration first when bootstrapping a new project.
Existing projects that already have `.claude/skills/agentic-apps-workflow/`
should NOT run 0000 — they are already past the baseline; they need
incremental migrations starting from their installed version.

## Pre-flight

```bash
# Project root must be a git repo (atomic commit per migration assumes git)
test -d .git || { echo "not a git repo — initialize first with: git init"; exit 1; }

# Refuse if already installed (use /update-agenticapps-workflow instead)
test -f .claude/skills/agentic-apps-workflow/SKILL.md && \
  { echo "AgenticApps workflow already installed — use /update-agenticapps-workflow"; exit 1; }
```

## Steps

### Step 1: Create `.claude/skills/agentic-apps-workflow/` and copy SKILL.md

**Idempotency check:** `test -f .claude/skills/agentic-apps-workflow/SKILL.md`
**Pre-condition:** the source skill file exists at the workflow scaffolder
location (`~/.claude/skills/agenticapps-workflow/skill/SKILL.md`)
**Apply:**
```bash
mkdir -p .claude/skills/agentic-apps-workflow
cp ~/.claude/skills/agenticapps-workflow/skill/SKILL.md .claude/skills/agentic-apps-workflow/SKILL.md
```
**Rollback:** `rm -rf .claude/skills/agentic-apps-workflow/`

### Step 2: Create `.claude/workflow-config.md` from template

**Idempotency check:** `test -f .claude/workflow-config.md`
**Pre-condition:** template exists at `~/.claude/skills/agenticapps-workflow/templates/workflow-config.md`
**Apply:** Copy the template and replace `{{PLACEHOLDERS}}` with project-specific
values gathered via interactive prompts. The setup skill is responsible for
gathering and substituting:

| Placeholder | Source |
|---|---|
| `{{PROJECT_NAME}}` | AskUserQuestion: "What is the project name?" |
| `{{REPO}}` | `git remote get-url origin` |
| `{{CLIENT}}` | AskUserQuestion: "Internal or which client?" |
| `{{BUDGET}}` | AskUserQuestion: "Budget tier (free / paid / enterprise)?" |
| `{{BACKEND}}` | AskUserQuestion: "Primary backend language?" |
| `{{FRONTEND}}` | AskUserQuestion: "Primary frontend stack?" |
| `{{DATABASE}}` | AskUserQuestion: "Primary database?" |
| `{{LLM}}` | AskUserQuestion: "Primary LLM provider?" |

```bash
cp ~/.claude/skills/agenticapps-workflow/templates/workflow-config.md .claude/workflow-config.md
# Then run interactive substitution per the table above
```
**Rollback:** `rm -f .claude/workflow-config.md`

### Step 3: Create `.planning/config.json` with hooks block

**Idempotency check:** `test -f .planning/config.json && jq -e '.hooks' .planning/config.json >/dev/null`
**Pre-condition:** template exists at `~/.claude/skills/agenticapps-workflow/templates/config-hooks.json`
**Apply:**
```bash
mkdir -p .planning
cp ~/.claude/skills/agenticapps-workflow/templates/config-hooks.json .planning/config.json
```
**Rollback:** `rm -f .planning/config.json && rmdir .planning 2>/dev/null || true`

### Step 4: Vendor CLAUDE.md workflow block + add reference to CLAUDE.md

**Idempotency check:** `test -f .claude/claude-md/workflow.md && grep -q "claude-md/workflow.md" CLAUDE.md`
**Pre-condition:** vendored template exists at `~/.claude/skills/agenticapps-workflow/templates/.claude/claude-md/workflow.md`
**Apply:**
```bash
# Create CLAUDE.md if missing
touch CLAUDE.md

# 4a — Vendor the workflow block as a project-local file
mkdir -p .claude/claude-md
cp ~/.claude/skills/agenticapps-workflow/templates/.claude/claude-md/workflow.md \
   .claude/claude-md/workflow.md

# 4b — Append a short reference block to CLAUDE.md (idempotency check above
# prevents double-append). The full content lives in the vendored file
# above; CLAUDE.md just links to it. This keeps CLAUDE.md inside the
# 200-line always-loaded budget.
cat >> CLAUDE.md <<'EOF'

## Workflow

This project uses the AgenticApps Superpowers + GSD + gstack workflow.
Full hooks, rituals, and red-flag tables: [`.claude/claude-md/workflow.md`](.claude/claude-md/workflow.md).
Vendored — re-sync via `/update-agenticapps-workflow`.
EOF
```

> **Why vendor instead of inline?** Earlier baseline behavior `cat`ed the
> entire ~150-line workflow template into CLAUDE.md, which blew the
> always-loaded context budget for any non-trivial project (cparx hit 646
> lines, fx-signal-agent 372). Vendoring as a separate file with a
> reference link keeps CLAUDE.md project-specific and inside budget while
> still making the workflow discoverable. ADR 0021 captures the rationale.

**Rollback:** Restore CLAUDE.md from git: `git checkout CLAUDE.md` if it
existed pre-step, else `rm -f CLAUDE.md`. Then
`rm -rf .claude/claude-md/`. Manual anchor for removal: delete the
`## Workflow` section appended by this step.

### Step 5: Append global CLAUDE.md additions (Option A install only)

**Skip condition:** if the project is per-project install (Option B/C), skip
this step entirely. Setup skill detects this via "did the user choose Option
A in the install prompt?".

**Idempotency check:** `grep -q "AgenticApps Workflow (Global)" ~/.claude/CLAUDE.md`
**Pre-condition:** template exists at `~/.claude/skills/agenticapps-workflow/templates/global-claude-additions.md`
**Apply:**
```bash
echo "" >> ~/.claude/CLAUDE.md
cat ~/.claude/skills/agenticapps-workflow/templates/global-claude-additions.md >> ~/.claude/CLAUDE.md
```
**Rollback:** Manual — open `~/.claude/CLAUDE.md` and delete the appended
block (anchored by `## AgenticApps Workflow (Global)`).

### Step 6: Bump installed version field to 1.2.0

**Idempotency check:** `grep -q '^version: 1.2.0' .claude/skills/agentic-apps-workflow/SKILL.md`
**Pre-condition:** Step 1 succeeded (skill file exists)
**Apply:** Edit `.claude/skills/agentic-apps-workflow/SKILL.md` frontmatter
to ensure the `version: 1.2.0` field is present. If the source SKILL.md was
copied with a `version` field already (which it should be from v1.2.0
forward), this step is a no-op. If the source was older and has no version
field, insert `version: 1.2.0` as the second frontmatter line (after `name:`).
**Rollback:** Remove the `version:` line.

## Post-checks

- `test -f .claude/skills/agentic-apps-workflow/SKILL.md` — installed
- `test -f .claude/workflow-config.md && grep -v '{{' .claude/workflow-config.md | head -1` — placeholders substituted
- `jq -e '.hooks.pre_phase.brainstorm_ui' .planning/config.json` — config valid
- `test -f .claude/claude-md/workflow.md` — workflow block vendored
- `grep -q "claude-md/workflow.md" CLAUDE.md` — CLAUDE.md links to vendored block
- `grep -q "Superpowers Integration Hooks (MANDATORY" .claude/claude-md/workflow.md` — vendored content sane
- `grep -q '^version: 1.2.0' .claude/skills/agentic-apps-workflow/SKILL.md` — version recorded

## Skip cases

- **Project already installed** (Step 1's pre-flight catches this) — exit
  with message pointing at `/update-agenticapps-workflow`.
- **No git repo** — exit with message asking the user to `git init` first.

## Notes

This migration cannot be tested non-interactively because Step 2 requires
`AskUserQuestion` responses. Validation is via running
`/setup-agenticapps-workflow` against a real fresh project and confirming
the post-checks pass. See `migrations/test-fixtures/README.md` for the
broader test harness contract.
