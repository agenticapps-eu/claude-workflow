# Migration framework

This directory holds **versioned migrations** that bring an installed AgenticApps
workflow from one version to the next. Every change to the workflow scaffolder
that affects projects on disk ships as a new migration file here.

The `setup` and `update` skills both consume migrations from this directory:

- `setup/SKILL.md` — applies all migrations from `0000-baseline.md` forward to
  the current version. This is what `/setup-agenticapps-workflow` runs on a
  fresh project.
- `update/SKILL.md` — applies only **pending** migrations (those with
  `from_version >` the project's installed version). This is what
  `/update-agenticapps-workflow` runs on an existing project.

There is no parallel "setup writes one shape, update writes a different shape"
code path. Both flows route through the same migration files.

---

## File naming

```
NNNN-{kebab-slug}.md
```

- `NNNN` — four-digit sequential ID (`0000`, `0001`, `0002`, …). Sequential
  IDs decouple "I have a new feature" from "what version number does that
  imply" — multiple migrations may fit inside one semver release.
- `kebab-slug` — short kebab-case description (`go-impeccable-database-sentinel`)
- Always Markdown (`.md`)

`0000-baseline.md` is special: it codifies the starting state of a fresh
project (currently the v1.2.0 default). Every other migration is incremental.

### Migration index (current chain)

| ID | from → to | Title |
|---|---|---|
| `0000` | unknown → 1.2.0 | Baseline (workflow files, hooks, **vendored** CLAUDE.md workflow block since v1.8.0) |
| `0001` | 1.2.0 → 1.3.0 | Wire Go skill packs + impeccable + database-sentinel |
| `0004` | 1.3.0 → 1.4.0 | Programmatic hooks + architecture audit + scheduling |
| `0002` | 1.4.0 → 1.5.0 | Observability spec v0.2.1 |
| `0008` | 1.7.0 → 1.8.0 | Coverage Matrix Page (per-repo presence + freshness dashboard) |
| `0009` | 1.7.0 → 1.8.0 | Vendor CLAUDE.md workflow block as `.claude/claude-md/workflow.md` |
| `0010` | 1.8.0 → 1.9.0 | Post-process GSD section markers in CLAUDE.md |
| `0005` | 1.9.0 → 1.9.1 | Multi-AI plan review enforcement (hook 6, gates `/gsd-review`) |
| `0006` | 1.9.1 → 1.9.2 | LLM wiki builder integration (plugin symlink + per-family scaffolding) |
| `0007` | 1.9.2 → 1.9.3 | GitNexus code-graph integration (MCP wire + helper script; user-initiated indexing) |

(IDs are not chronological — see "Application order" below for why
`0004` runs before `0002` in the chain. Application order is by
`from_version` matching, not by ID.)

---

## Application order

Migrations are applied by **`from_version` matching**, not by ID order. The
`update` skill repeatedly looks at the project's currently-installed version,
finds the migration whose `from_version` matches, applies it, and bumps the
project to that migration's `to_version`. It loops until no more matching
migration is found.

This decouples the file's sequential ID from its place in the version chain.
Two consequences worth stating explicitly:

1. **IDs and versions can be out of sync.** A project on `1.3.0` runs
   migration `0004` (`1.3.0 → 1.4.0`) before migration `0002` (`1.4.0 →
   1.5.0`), even though `0004 > 0002` numerically. The IDs identify
   migrations; they don't sequence them.

2. **Two migrations MUST NOT share the same `from_version`.** If both
   `0002` and `0007` had `from_version: 1.4.0`, the update skill would have
   no rule for picking one. Releases that need parallel branches (e.g. a
   1.4.x security patch alongside an in-flight 1.5.0 feature) get one
   `to_version` each — `1.4.1` for the patch, `1.5.0` for the feature —
   so the chain stays linear.

If you're authoring a migration, the safe pattern is:

- Pick the next free `to_version` per semver (patch for clarifications,
  minor for additive, major for breaking).
- Set `from_version` to the highest currently-released `to_version` your
  migration needs to chain after.
- Pick the next free `id` numerically — it doesn't need to be one greater
  than the last migration that ran chronologically.

The drift-report tool (`tools/drift-report.sh` in core) flags any chain
gap or duplicate `from_version` automatically.

---

## File format

Every migration file uses this structure:

```markdown
---
id: 0001
slug: go-impeccable-database-sentinel
title: Wire Go skills + impeccable + database-sentinel into AgenticApps workflow
from_version: 1.2.0
to_version: 1.3.0
applies_to:
  - .claude/workflow-config.md
  - .planning/config.json
  - CLAUDE.md
  - docs/decisions/
requires:
  - skill: impeccable
    install: "npx skills add pbakaus/impeccable"
    verify: "test -f ~/.claude/skills/impeccable/SKILL.md"
  - skill: database-sentinel
    install: "git clone https://github.com/Farenhytee/database-sentinel ~/.claude/skills/database-sentinel"
    verify: "test -f ~/.claude/skills/database-sentinel/SKILL.md"
optional_for:
  - tag: go
    detect: "find . -name '*.go' -not -path '*/node_modules/*' -not -path '*/vendor/*' | head -1 | grep -q ."
    note: "If no Go files detected, the routing rows still install but the runtime won't trigger them."
---

# Migration 0001 — {title}

## Pre-flight
{commands the update skill runs before any patch}

## Steps

### Step 1: {short description}
**Idempotency check:** `grep -q "..." path/to/file`
**Pre-condition:** the file exists and has a `## Conventions` section
**Apply:**
{exact patch as a fenced code block}
**Rollback:** {how to revert this step}

### Step 2: ...
{...}

## Post-checks
- All `grep` verifications pass (the same checks from action plan §0/§1/§2)
- `cat .planning/config.json | jq` validates structure
- ADR opportunity: prompt user whether to draft ADRs for each adopted hook

## Skip cases
- Project has no `.planning/` directory → migration skipped with note "no GSD setup detected; use /setup-agenticapps-workflow first"
- Project's `from_version` already ≥ this migration's `to_version` → skipped silently
```

### Frontmatter fields

| Field | Required | Meaning |
|---|---|---|
| `id` | ✅ | Sequential migration ID (matches filename prefix) |
| `slug` | ✅ | Kebab-case slug (matches filename middle) |
| `title` | ✅ | Human-readable one-line title |
| `from_version` | ✅ | Installed version that this migration upgrades **from**. Skip if installed `<` this. |
| `to_version` | ✅ | Version after this migration successfully applies. Update skill writes this to the project's installed-version field. |
| `applies_to` | ✅ | List of files / directories this migration touches (for impact awareness in the plan output) |
| `requires` | optional | List of external skills that must be installed before applying. Each: `skill`, `install` command, `verify` test. |
| `optional_for` | optional | List of conditional steps. Each: `tag`, `detect` shell command, `note`. Steps tagged with the same `tag` are skipped if `detect` returns non-zero. |

### Step structure

Every step has four mandatory fields:

| Field | Purpose |
|---|---|
| `Idempotency check` | Shell command that returns 0 if the step has already been applied. The update skill skips applied steps without prompting. |
| `Pre-condition` | Shell command that must return 0 before the step can apply (e.g. "the file exists and has the section we're patching"). If pre-condition fails, the step errors with a specific message rather than silently producing wrong output. |
| `Apply` | The exact patch — markdown content to insert, JSON entry to add, file to create. Applied as-is by the update skill (with the agent's interpretation, since the skill is markdown not executable). |
| `Rollback` | How to revert this step. Either a unique anchor comment to delete, or an explicit `git revert` instruction, or "manual — see VERIFICATION.md for resolution". |

---

## Idempotency contract

Every step MUST be safely re-runnable. Running the same migration twice in a
row must produce: 1 actual apply, 1 "skipped (already applied)" log line.

The idempotency check is the contract:

- **For markdown insertions:** check for a unique anchor string from the new
  content (e.g. `grep -q "^## Backend language routing" .claude/workflow-config.md`).
- **For JSON modifications:** check for a unique key path
  (`jq -e '.hooks.pre_phase.design_critique' .planning/config.json >/dev/null`).
- **For file creation:** check the file exists at the expected path with
  expected content (`test -f templates/adr-db-security-acceptance.md`).

A migration without working idempotency checks is a defective migration. The
update skill will refuse to apply it twice; the second run will error.

---

## Atomicity contract

If step N fails halfway, the update skill prompts the user with three options:

1. **Retry** — re-run step N (idempotent steps are safe to re-run)
2. **Skip with warning** — log the skip, continue with step N+1 (the migration
   is marked partial in the version-bump record)
3. **Rollback** — apply rollback patches for steps 1..N-1 (using each step's
   `Rollback` clause), restore the project to its pre-migration state

Default: prompt user. The update skill never auto-rolls-back without consent,
because partial-state recovery may be more useful than full revert.

---

## Dry-run mode

`update-agenticapps-workflow --dry-run` runs every step's idempotency check
and **prints the diff each step would apply** without writing or committing.
This is the default-on-confirm interactive mode: dry-run the whole chain,
show diffs, then ask "apply now?".

---

## Where the workflow scaffolder lives

Migrations reference the workflow scaffolder repo's own files using the
canonical install path:

```
~/.claude/skills/agenticapps-workflow/
```

This is the path the README's Option A install command produces (`git clone
… ~/.claude/skills/agenticapps-workflow`). The **project-side** copy that
setup creates uses a slightly different name (`.claude/skills/agentic-apps-workflow/`
with a hyphen) — this is intentional, distinguishing the scaffolder repo
from each project's local skill copy. All migrations use the canonical
scaffolder path; if a user installed under a different path, they should
symlink or `--scaffolder PATH` (future enhancement) rather than the
migration adapting to non-canonical installs.

## Where the installed version lives

Each project records its installed AgenticApps workflow version in the
frontmatter of its local skill copy:

```
.claude/skills/agentic-apps-workflow/SKILL.md
---
name: agentic-apps-workflow
version: 1.3.0   ← here
description: |
  ...
---
```

The update skill reads this field via simple frontmatter parsing. Bare
projects with no version field are treated as `from_version = unknown`
and routed through `/setup-agenticapps-workflow` rather than upgraded.

---

## Test fixtures

`migrations/test-fixtures/` contains a fixture-based test harness for
migrations. See `test-fixtures/README.md` for the contract, and
`migrations/run-tests.sh` for the runner. Every migration that operates on
existing files (i.e. every migration except 0000-baseline) ships with a
matching test fixture pair (before-state, expected-after-state) and a
runner assertion that the migration produces the expected end-state.

`0000-baseline.md` does not have a non-interactive test because it requires
user input via `AskUserQuestion`; its correctness is validated by running
`/setup-agenticapps-workflow` against a real fresh project.

---

## Adding a new migration

1. Pick the next sequential ID (`ls migrations/[0-9]*.md | tail -1`).
2. Create `NNNN-slug.md` with the frontmatter + steps + post-checks per
   the format above.
3. Each step ships with idempotency check + rollback.
4. Add a fixture pair under `migrations/test-fixtures/` covering the
   before-state and expected-after-state.
5. Run `migrations/run-tests.sh NNNN` and confirm green.
6. Bump the workflow skill version in `skill/SKILL.md` frontmatter to the
   migration's `to_version`.
7. Open a PR. Code review must include: dry-run output for the migration
   applied to a real existing project; test runner output green.
