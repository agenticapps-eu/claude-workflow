---
name: setup-agenticapps-workflow
description: |
  Bootstrap a fresh project with the AgenticApps Superpowers + GSD + gstack
  workflow by installing the LATEST snapshot directly — no migration replay.
  Lays down the current end-state project artifacts (the workflow skill,
  CLAUDE.md sections, hooks, settings, planning config, version stamp) in one
  shot. Use when the user runs "/setup-agenticapps-workflow", "set up the
  workflow", "install agenticapps workflow", or "scaffold this project".
  Idempotent — refuses to re-run on a project that already has
  `.claude/skills/agentic-apps-workflow/` and routes to
  `/update-agenticapps-workflow` instead. Fail-closed on an unverified
  snapshot: refuses to install until the drift guard
  (`check-snapshot-parity.sh`) passes, so a raw/stale seed can never be laid
  down silently.
---

# Setup AgenticApps Workflow

Bootstrap a project straight to the **latest** AgenticApps workflow version by
laying down a prebuilt snapshot. Setup does **not** replay the migration chain.

## Why snapshot, not replay (ADR-0036)

Previously setup applied every migration `0000-baseline` → latest, sharing one
code path with update. That made a brand-new project re-execute 20+ migrations
of history to reach the current shape, and forced every historical migration to
stay replayable against an empty repo forever.

This skill diverges (see `docs/decisions/0036-snapshot-install.md`):

- **Fresh install → snapshot.** Copy the current end-state from
  `setup/snapshot/`, substitute placeholders, stamp the version. One step.
- **Existing install → migrations.** `/update-agenticapps-workflow` is
  unchanged: it applies only pending migrations (`from_version >` the
  installed version).

The snapshot is materialized by replaying the whole chain once
(`bin/build-snapshot.sh`) and kept honest by a drift guard
(`migrations/check-snapshot-parity.sh`) that CI runs on every PR. So "skip
replay on fresh install" never ships a stale baseline.

## Step 0: Parse flags

| Flag | Effect |
|---|---|
| `--dry-run` | Show every file the snapshot would write/modify, without writing or committing. |
| `--scope A\|B\|C` | Skip the Step 2 prompt and use the given install scope. |

(The `--target-version` flag is gone — snapshot install always lands the
latest. To reproduce a historical version, install latest then
`/update-agenticapps-workflow --target-version V` is not supported backwards;
check out the scaffolder at the desired tag and re-run setup.)

## Step 1: Pre-flight

```bash
# Project root must be a git repo
test -d .git || { echo "ERROR: not a git repo. Run 'git init' first."; exit 1; }

# Refuse if already installed
if [ -f .claude/skills/agentic-apps-workflow/SKILL.md ]; then
  INSTALLED=$(awk '/^---$/{f++; next} f==1 && /^version:/ {print $2; exit}' .claude/skills/agentic-apps-workflow/SKILL.md)
  echo "ERROR: AgenticApps workflow already installed (version $INSTALLED)."
  echo "Use /update-agenticapps-workflow to upgrade."
  exit 1
fi

# Scaffolder + snapshot must be present
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
SNAP="$SCAFFOLDER/setup/snapshot"
test -d "$SNAP" || {
  echo "ERROR: snapshot not found at $SNAP."
  echo "Install the scaffolder: git clone https://github.com/agenticapps-eu/claude-workflow.git $SCAFFOLDER"
  echo "If the clone exists but snapshot/ is empty, run: bash $SCAFFOLDER/bin/build-snapshot.sh"
  exit 1
}
LATEST=$(cat "$SNAP/VERSION")

# Snapshot must be VERIFIED (materialized from the migration chain), not the raw
# seed. The seed lags the latest migrations and would install a known-incorrect
# baseline (wrong settings.json keys, missing hook bindings, stale config).
# Fail closed: run the drift guard and refuse unless it passes. See
# docs/decisions/0036-snapshot-install.md and setup/snapshot/MANIFEST.md.
PARITY="$SCAFFOLDER/migrations/check-snapshot-parity.sh"
if [ ! -x "$PARITY" ]; then
  echo "ERROR: drift guard not found at $PARITY — cannot verify the snapshot."
  echo "Refusing to install an unverified snapshot."
  exit 1
fi
if ! _out=$(bash "$PARITY" 2>&1); then
  echo "ERROR: the setup snapshot is UNVERIFIED — still the raw seed, or drifted"
  echo "from the migration chain. It has not been materialized by build-snapshot.sh,"
  echo "so installing it would lay down a known-stale / incorrect baseline."
  echo ""
  echo "Fix: materialize it until the drift guard passes, then re-run setup:"
  echo "  bash $SCAFFOLDER/bin/build-snapshot.sh"
  echo "To bootstrap now, use a scaffolder checked out at a released tag whose"
  echo "snapshot is already verified. See docs/decisions/0036-snapshot-install.md."
  echo ""
  printf '%s\n' "$_out" | sed 's/^/  parity: /' | head -20
  exit 1
fi

# Optional tooling (warn, don't fail)
command -v claude >/dev/null 2>&1 || echo "WARN: claude CLI not on PATH"
ls ~/.claude/get-shit-done/bin/gsd-tools.cjs >/dev/null 2>&1 || echo "WARN: GSD not installed"
ls ~/.claude/skills/gstack/VERSION >/dev/null 2>&1 || echo "WARN: gstack not installed"
ls ~/.claude/plugins/cache/claude-plugins-official/superpowers/ >/dev/null 2>&1 || echo "WARN: superpowers plugin not installed"
```

## Step 2: Choose install scope

Use AskUserQuestion (skip if `--scope` was passed):

> How should this workflow be installed?
> A) Per-project (project-local) — scoped to this repo only.  [Recommended]
> B) Global (~/.claude/CLAUDE.md additions) — applies across all projects.
> C) Both.

Record `$SCOPE` (`per-project` / `global` / `both`). It drives whether Step 4f
(global CLAUDE.md additions) runs.

## Step 3: Gather project details (for placeholder substitution)

Same placeholders as before — gather up-front via AskUserQuestion (auto-fill
derivable ones):

| Placeholder | Source |
|---|---|
| `{{PROJECT_NAME}}` | "Project name?" (default `basename $(pwd)`) |
| `{{REPO}}` | `git remote get-url origin` (else ask) |
| `{{CLIENT}}` | "Client (or 'internal')?" |
| `{{BUDGET}}` | free / paid / enterprise |
| `{{BACKEND}}` | Go / Node / Python / Ruby / Other |
| `{{FRONTEND}}` | React / Vue / Svelte / None / Other |
| `{{DATABASE}}` | Postgres / Supabase / MongoDB / Firebase / None / Other |
| `{{LLM}}` | Anthropic / OpenAI / Both / None / Other |

## Step 4: Lay down the snapshot (no migration replay)

Resolve `$SNAP`. Each step is idempotent (skip if the target already exists);
in `--dry-run` show the diff instead of writing.

a. **Workflow skill** — `mkdir -p .claude/skills/agentic-apps-workflow` and copy
   `$SNAP/agentic-apps-workflow-SKILL.md` →
   `.claude/skills/agentic-apps-workflow/SKILL.md`. Its `version:` frontmatter
   is already `$LATEST` (this is the installed-version record).

b. **Project config** — copy `$SNAP/workflow-config.md` →
   `.claude/workflow-config.md`, substitute every `{{PLACEHOLDER}}` with Step 3
   values. Fail if any `{{...}}` remains.

c. **Hooks + settings** — copy `$SNAP/claude-settings.json` →
   `.claude/settings.json`, and `$SNAP/hooks/*` → `.claude/hooks/` (chmod +x),
   and `$SNAP/scripts/*` → `.claude/scripts/`.

d. **Planning hooks** — `mkdir -p .planning` and copy `$SNAP/planning-config.json`
   → `.planning/config.json`. This is the **latest** hooks block (every
   migration's hook already folded in) — no incremental edits follow.

e. **Vendored CLAUDE.md block + reference** — `mkdir -p .claude/claude-md` and
   copy `$SNAP/claude-md-workflow.md` → `.claude/claude-md/workflow.md`. Then,
   if `CLAUDE.md` does not already reference it, append the reference block from
   `$SNAP/claude-md-reference-block.md` to `CLAUDE.md` (create `CLAUDE.md` if
   missing). Never duplicate the reference.

f. **Global additions (scope B/C only)** — append
   `$SNAP/global-claude-additions.md` to `~/.claude/CLAUDE.md`. Skip for
   `per-project`.

g. **ADR template** — copy `$SNAP/adr-db-security-acceptance.md` →
   `templates/adr-db-security-acceptance.md` if absent.

## Step 5: Post-checks and commit

Post-checks (fail the install, do not commit, if any fail):

- `.claude/skills/agentic-apps-workflow/SKILL.md` exists; its `version:` reads `$LATEST`
- `.claude/workflow-config.md` exists with no `{{...}}` left
- `.planning/config.json` is valid JSON with the `hooks` block
- `.claude/claude-md/workflow.md` exists and `CLAUDE.md` references it
- the snapshot's latest features are present (proves it's not the v1.2.0
  baseline): `grep -rq "prompt.injection\|injection-defense" .claude` and the
  ts-declare-first hook/skill are wired per the manifest

```bash
git add -A
git commit -m "chore: install agenticapps-workflow v$LATEST (snapshot)"
```

## Step 6: Summary

```
Setup complete — agenticapps-workflow v{LATEST} (snapshot install, no replay).

Files created:
  - .claude/skills/agentic-apps-workflow/SKILL.md   (workflow skill)
  - .claude/workflow-config.md                      (project config)
  - .claude/settings.json + .claude/hooks/*         (enforcement hooks)
  - .planning/config.json                           (hook bindings)
  - .claude/claude-md/workflow.md                   (vendored workflow block)
  - CLAUDE.md                                       (## Workflow reference)
  {scope global/both:} ~/.claude/CLAUDE.md          (global additions)

Next:
  - /agentic-apps-workflow to start your first phase.
  - Future updates: /update-agenticapps-workflow (applies pending migrations).
```

## Failure modes

| Failure | Behavior |
|---|---|
| Not a git repo | Error in Step 1; suggest `git init`; exit 1 |
| Already installed | Error in Step 1; route to `/update-agenticapps-workflow`; exit 1 |
| Snapshot missing/empty | Error in Step 1; suggest `bash bin/build-snapshot.sh`; exit 1 |
| Unverified/seed snapshot | Error in Step 1; the drift guard fails → setup refuses (fail-closed) rather than install a stale baseline; run `bin/build-snapshot.sh` first; exit 1 |
| Unsubstituted placeholder | Post-check fails the install rather than committing `{{...}}` |
| Stale snapshot | Cannot ship silently — `check-snapshot-parity.sh` fails CI (and now Step 1) if `snapshot/` ≠ replay(0000→latest) |

## Idempotency

Re-running setup errors in Step 1 (refuses if installed). Re-application is the
job of `/update-agenticapps-workflow`. The per-file idempotency checks in Step 4
make a partially-failed setup safe to resume.

## Reference: related skills

- `update-agenticapps-workflow` — applies pending migrations to an
  already-installed workflow (the migration path lives here now).
- `agentic-apps-workflow` — the workflow itself; setup installs the project copy.
- `bin/build-snapshot.sh` — regenerates `setup/snapshot/` from the migration
  chain. Run after adding a migration so the drift guard stays green.
