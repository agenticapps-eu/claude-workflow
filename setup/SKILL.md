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

The snapshot is materialized by `bin/build-snapshot.sh`, which assembles it
deterministically from the maintained sources (`templates/` + `skill/SKILL.md`) —
the migration chain is not shell-replayed (see ADR-0036). It is kept honest by a
drift guard (`migrations/check-snapshot-parity.sh`) that CI runs on every PR, so
"skip replay on fresh install" never ships a stale baseline.

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

d. **Planning hooks** — `mkdir -p .planning` and:
   - If `.planning/config.json` does **not** exist: copy
     `$SNAP/planning-config.json` → `.planning/config.json`. (The snapshot owns
     only `.hooks`; `.workflow` is GSD-owned config written by GSD at its own
     init — setup must not overwrite it.)
   - If `.planning/config.json` **does** exist (e.g. GSD already wrote it,
     including its `.workflow` block): merge the snapshot's `.hooks` into the
     existing file without clobbering other sections:
     ```bash
     jq -s '.[0] * .[1]' .planning/config.json "$SNAP/planning-config.json" > .planning/config.json.tmp \
       && mv .planning/config.json.tmp .planning/config.json
     ```
     (Snapshot second so its `.hooks` wins; `*` deep-merges, preserving a
     GSD-written `.workflow`.)
   - **Knowledge capture (spec §15)** — the snapshot config seeds a
     `knowledge_capture` block whose `note` carries a literal `<repo-name>`
     placeholder. Resolve it now to the actual repo directory name (per §15.2
     the name is written out literally at configuration time — never
     substituted at runtime):
     ```bash
     REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"
     jq --arg name "$REPO_NAME" \
       '.knowledge_capture.note |= gsub("<repo-name>"; $name)' \
       .planning/config.json > .planning/config.json.tmp \
       && mv .planning/config.json.tmp .planning/config.json
     ```
     The block references only the operator's vault path — never a
     claude-workflow path — so the repo stays self-contained. Machines without
     the vault folder are silent by design (the skill's graceful skip).
   - In `--dry-run`: show the diff instead of writing.

e. **Vendored CLAUDE.md block + reference** — `mkdir -p .claude/claude-md` and
   copy `$SNAP/claude-md-workflow.md` → `.claude/claude-md/workflow.md`. Then,
   if `CLAUDE.md` does not already reference it, append the reference block from
   `$SNAP/claude-md-reference-block.md` to `CLAUDE.md` (create `CLAUDE.md` if
   missing). Never duplicate the reference.

e2. **§11 canonical block (spec §11 — CLAUDE.md)** — inject the canonical
   "Coding Discipline" block into `CLAUDE.md` behind a provenance anchor,
   byte-identical to what migration 0014 produces on the replay path. §11
   requires the block verbatim in the project's PRIMARY instruction file, so
   it goes in `CLAUDE.md` itself — not in `.claude/claude-md/workflow.md`.

   Refuse rather than overwrite a hand-pasted block:

   ```bash
   SPEC11="$SNAP/spec-mirrors/11-coding-discipline-0.4.0.md"
   PROV='<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->'
   PROV_RE='<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->'

   test -f "$SPEC11" || { echo "ABORT: snapshot missing $SPEC11"; exit 3; }

   if grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md \
      && ! grep -qE "$PROV_RE" CLAUDE.md; then
     echo "ABORT: CLAUDE.md has a '## Coding Discipline (NON-NEGOTIABLE)' heading"
     echo "       with no provenance comment — it was hand-pasted outside this"
     echo "       installer's management. Remove that section and re-run, or add"
     echo "       the line '$PROV' immediately above the heading to adopt it."
     exit 3
   fi

   if ! grep -qE "$PROV_RE" CLAUDE.md; then
     awk -v prov="$PROV" -v bf="$SPEC11" '
       function emit(  line) {
         print prov
         while ((getline line < bf) > 0) print line
         close(bf)
         print ""
       }
       BEGIN { done = 0 }
       !done && /^## / { emit(); done = 1 }
       { print }
       END { if (!done) emit() }
     ' CLAUDE.md > CLAUDE.md.spec11.tmp && mv CLAUDE.md.spec11.tmp CLAUDE.md
     echo "INFO: injected §11 canonical block into CLAUDE.md"
   fi
   ```

   The `END` branch is the fallback for a `CLAUDE.md` with no `## ` heading at
   all — the block is appended rather than dropped.

   Setup needs only two of migration 0014's three branches: setup refuses to
   re-run on an installed project (it routes to `/update`), so a CLAUDE.md
   already carrying OUR provenance anchor is unreachable here. 0014's
   stale-provenance replace branch is therefore dead code on this path.

   - In `--dry-run`: show the diff instead of writing.

f. **Global additions (scope B/C only)** — append
   `$SNAP/global-claude-additions.md` to `~/.claude/CLAUDE.md`. Skip for
   `per-project`.

g. **ADR template** — copy `$SNAP/adr-db-security-acceptance.md` →
   `templates/adr-db-security-acceptance.md` if absent.

h. **`.gitignore` (commit phase artifacts — ADR-0037)** — the snapshot's
   `$SNAP/gitignore` is the canonical baseline: it commits `.planning/phases/`
   and ignores only local/ephemeral paths. Merge, never clobber a project's
   existing stack ignores:
   - If `.gitignore` does **not** exist: copy `$SNAP/gitignore` → `.gitignore`.
   - If `.gitignore` **does** exist: **(1)** strip any whole-tree phases ignore
     the project may carry (the friction this fixes) —
     ```bash
     sed -i.bak -E '/^[[:space:]]*\/?\.planning\/phases\/?[[:space:]]*$/d; /^[[:space:]]*\/?\.planning\/?[[:space:]]*$/d' .gitignore && rm -f .gitignore.bak
     ```
     then **(2)** append any managed line from `$SNAP/gitignore` not already
     present (dedupe by exact line), so the narrow local ignores are ensured
     without duplicating or reordering the project's own entries.
   - In `--dry-run`: show the diff instead of writing.
   - Phase artifacts (`CONTEXT.md`, `PLAN.md`, `VERIFICATION.md`, `REVIEW.md`,
     `HANDOFF-LOG.md`) MUST remain committed — never re-add `.planning/phases/`.

i. **`.prettierignore` (exclude vendored hooks — migration 0028)** — the
   GitNexus reindex hook (`.claude/hooks/gitnexus-reindex.cjs`) is a CommonJS
   Node hook; a project that runs `prettier --check` over `.claude/` would fail
   on it. **Append-if-exists only** — never create the file:
   ```bash
   if [ -f .prettierignore ] && ! grep -qE '^\.claude/hooks/?$' .prettierignore; then
     printf '\n# AgenticApps workflow (0028): vendored .claude hooks are .cjs/.sh Node\n# tooling, not app code; exclude from prettier --check.\n.claude/hooks/\n' >> .prettierignore
   fi
   ```
   A project without a `.prettierignore` never configured Prettier ignores;
   creating one would imply tooling it does not use (the same conservative
   stance §15 takes with an absent vault). ESLint needs no equivalent — the
   shipped hook carries a file-level `eslint-disable` header.
   - In `--dry-run`: show the diff instead of writing.

## Step 5: Post-checks and commit

Post-checks (fail the install, do not commit, if any fail):

- `.claude/skills/agentic-apps-workflow/SKILL.md` exists; its `version:` reads `$LATEST`
- `.claude/workflow-config.md` exists with no `{{...}}` left
- `.planning/config.json` is valid JSON with the `hooks` block
- `.planning/config.json` carries the `knowledge_capture` block with its
  `<repo-name>` placeholder resolved:
  `jq -e '.knowledge_capture.enabled | type == "boolean"' .planning/config.json`
  and `! grep -qF '<repo-name>' .planning/config.json`
- `.claude/claude-md/workflow.md` exists and `CLAUDE.md` references it
- the snapshot's latest features are present (proves it's not an old baseline):
  the spec §15 knowledge-capture ritual tail is in the installed skill —
  `grep -q '^## Knowledge Capture — Ritual Tail' .claude/skills/agentic-apps-workflow/SKILL.md`
  (§14 prompt-injection is delegated to the `injection-guard` skill at migration
  0023, so it is intentionally NOT baked into the snapshot's `.claude` payload)
- `.gitignore` exists and does **not** ignore the `.planning/phases/` tree
  (ADR-0037): `! grep -qE '^[[:space:]]*/?\.planning/phases/?[[:space:]]*$' .gitignore`
- `CLAUDE.md` carries the §11 canonical block under provenance:
  `grep -q '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->' CLAUDE.md`
  and `grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md`

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
  - .planning/config.json                           (hook bindings + knowledge capture)
  - .claude/claude-md/workflow.md                   (vendored workflow block)
  - CLAUDE.md                                       (§11 block + ## Workflow reference)
  - .gitignore                                      (commits .planning/phases/)
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
| Stale snapshot | Cannot ship silently — `check-snapshot-parity.sh` fails CI (and now Step 1) if `snapshot/` ≠ the deterministic assembly from `templates/` + `skill/SKILL.md` |

## Idempotency

Re-running setup errors in Step 1 (refuses if installed). Re-application is the
job of `/update-agenticapps-workflow`. The per-file idempotency checks in Step 4
make a partially-failed setup safe to resume.

## Reference: related skills

- `update-agenticapps-workflow` — applies pending migrations to an
  already-installed workflow (the migration path lives here now).
- `agentic-apps-workflow` — the workflow itself; setup installs the project copy.
- `bin/build-snapshot.sh` — regenerates `setup/snapshot/` by assembling it
  deterministically from the maintained sources (`templates/` + `skill/SKILL.md`).
  Run after adding a migration or editing a template so the drift guard stays green.
