---
name: update-agenticapps-workflow
description: |
  Upgrade an existing AgenticApps project's workflow skill to the latest
  version by applying pending migrations from the claude-workflow repo's
  migrations/ directory. Use when the user runs "/update-agenticapps-workflow",
  "upgrade workflow", or after pulling a new claude-workflow release.
  Handles version detection, migration discovery, pre-flight skill installs,
  per-step diff preview + confirm, idempotent reapplication, and rollback
  on failure. Supports --dry-run, --migration N, and --from V flags.
---

# Update AgenticApps Workflow

This skill upgrades a project's installed AgenticApps workflow by applying
pending migrations from the workflow scaffolder repo. It is the migration
runtime — the migrations themselves are content files at
`~/.claude/skills/agenticapps-workflow/migrations/NNNN-slug.md`.

The companion skill `setup-agenticapps-workflow` uses the same migration
infrastructure to bootstrap fresh projects (it applies all migrations from
`0000-baseline.md` forward). There is no parallel "setup writes one shape,
update writes another" code path.

## Step 0: Parse flags

Recognize these optional flags:

| Flag | Effect |
|---|---|
| `--dry-run` | Show every step's diff without writing or committing. No state changes. |
| `--migration N` | Apply only migration `NNNN` (zero-padded), even if other migrations are pending. Advanced — for retry of a single failed migration. |
| `--from V` | Override the detected installed version. Advanced — for projects with a corrupt or missing version field. |
| (none) | Default interactive mode: detect, plan, dry-run preview, confirm, apply. |

If multiple flags are passed, honor them in order: `--from V` resets the
version, then `--migration N` filters which migration to apply, then
`--dry-run` toggles whether to write.

## Step 1: Detect installed version

```bash
SKILL_FILE=".claude/skills/agentic-apps-workflow/SKILL.md"
if [ ! -f "$SKILL_FILE" ]; then
  echo "ERROR: no AgenticApps workflow installed at $SKILL_FILE"
  echo "Run /setup-agenticapps-workflow first to install."
  exit 1
fi

INSTALLED=$(awk '/^---$/{f++; next} f==1 && /^version:/ {print $2; exit}' "$SKILL_FILE")
if [ -z "$INSTALLED" ]; then
  echo "ERROR: $SKILL_FILE has no 'version' field in its frontmatter."
  echo "Either run /setup-agenticapps-workflow to repair, or rerun this skill"
  echo "with --from <version> to override the detected version."
  exit 1
fi
echo "Detected installed version: $INSTALLED"
```

If `--from V` was passed, override `$INSTALLED` with `V`.

## Step 2: Find pending migrations

```bash
MIGRATIONS_DIR=~/.claude/skills/agenticapps-workflow/migrations

# Read every migration's frontmatter
for migration in "$MIGRATIONS_DIR"/[0-9]*.md; do
  ID=$(awk '/^---$/{f++; next} f==1 && /^id:/ {print $2; exit}' "$migration")
  FROM=$(awk '/^---$/{f++; next} f==1 && /^from_version:/ {print $2; exit}' "$migration")
  TO=$(awk '/^---$/{f++; next} f==1 && /^to_version:/ {print $2; exit}' "$migration")
  TITLE=$(awk '/^---$/{f++; next} f==1 && /^title:/ {sub(/^title: /, ""); print; exit}' "$migration")
  # Pending if installed >= FROM and installed < TO
  # Use semver-aware comparison (sort -V handles 1.2.0 vs 1.10.0 correctly)
  if [ "$(printf '%s\n%s\n' "$FROM" "$INSTALLED" | sort -V | head -1)" = "$FROM" ] && \
     [ "$INSTALLED" != "$TO" ] && \
     [ "$(printf '%s\n%s\n' "$INSTALLED" "$TO" | sort -V | head -1)" = "$INSTALLED" ]; then
    echo "PENDING: $ID  $FROM → $TO  $TITLE"
  fi
done | sort
```

If `--migration N` was passed, filter the list to only that migration ID
(skip the version-range check; let the user force the run).

If no migrations are pending, print:
```
Up to date. Installed version: $INSTALLED. No pending migrations in $MIGRATIONS_DIR.
```
And exit cleanly (status 0).

## Step 3: Show migration plan

For each pending migration, print:

```
{ID} {FROM_VERSION} → {TO_VERSION}: {TITLE}
  Required skills:
    - {skill}: install via `{install command}` (verify: `{verify command}`)
  Files affected:
    - {applies_to entry}
    - ...
  Number of steps: {count of "### Step" headings}
```

Then ask the user (via AskUserQuestion):

> Apply N migrations now?
> A) Apply all (with per-step diff preview + confirm)  [Recommended]
> B) Dry-run only — show diffs but don't write
> C) Cancel

If user picks B, set the dry-run flag for the remainder of this run.
If user picks C, exit cleanly.

If `--dry-run` was passed at invocation, skip this question and proceed
with dry-run mode automatically.

## Step 4: Pre-flight per migration

For each pending migration in order:

1. Read the `requires` block from frontmatter.
2. For each required skill, run its `verify` command.
3. If verification fails, present:
   ```
   Migration {ID} requires skill "{skill}" which is not installed.
   Install command: {install command}
   ```
   Ask the user (via AskUserQuestion):
   > A) Pause — I'll install it manually, then resume  [Recommended]
   > B) Skip this migration (with warning)
   > C) Cancel the entire update
4. Do NOT auto-install missing skills. Keep this skill's blast radius tight —
   external `npx`/`git clone` happens only with explicit user authorization
   in their own shell.

Run the migration's `## Pre-flight` block (a shell snippet in the migration
file) and abort the migration if it fails (with the error message it
prints).

## Step 5: Apply each migration

For each pending migration:

For each step (parsed from `### Step N:` headings):

1. Run the **Idempotency check** shell snippet.
   - If returns 0: log `step {N}: skipped (already applied)`. Continue to next step.
   - If returns non-zero: proceed to step 2.

2. Run the **Pre-condition** check.
   - If returns non-zero: stop the migration. Report the pre-condition that
     failed and ask the user to either fix the pre-condition (then retry)
     or skip this step (logged in the migration's outcome).

3. **Show the diff** the step would apply. For markdown insertions, format
   as a unified diff against the current file. For JSON modifications,
   format as `jq` output before/after. For file creation, show the file's
   intended content. **For vendored-file replacement** (e.g. migration
   0009 Step 1 / Step 2 re-syncing `.claude/claude-md/workflow.md`),
   detect divergence by byte-comparing the existing project copy against
   the canonical source in the workflow scaffolder. If they differ, treat
   this as a divergence event (see "Divergence detection" below).

4. If `--dry-run`: log `step {N}: would apply (dry-run, no write)`. Continue.

5. Otherwise, ask via AskUserQuestion:
   > Apply step {N}?
   > A) Apply [Recommended]
   > B) Skip with warning
   > C) Abort migration (rollback applied steps)
   > D) Show full migration step text again

   **Divergence variant** (when Step 3 detected a customised local copy
   of a vendored file): present a 3-way pick instead of the standard A/B/C/D:
   > Local copy of `<path>` differs from the v{TO_VERSION} canonical template:
   > A) Replace with canonical (overwrites local edits) [Recommended only if
   >    you know the local edits were not intentional]
   > B) Keep local copy (skip this step; re-sync manually if a future
   >    migration substantively changes the canonical) [Recommended for
   >    intentionally customised vendored files]
   > C) Vendor the local (customised) copy as the canonical going forward
   >    (treats your edits as authoritative; the canonical from the
   >    scaffolder is overwritten in the project's local copy) [advanced]
   > D) Show full diff again
   > E) Abort migration (rollback applied steps)

   The diff is `diff -u <scaffolder-source> <project-local-copy>`. The
   default selection on this prompt is **B (Keep local copy)** — diverging
   is usually intentional, and the safe action is to leave it alone.

6. On Apply: write the patch. The actual mechanism depends on step type:
   - Markdown insertion: Edit the target file.
   - JSON modification: use `jq` (or Edit if jq isn't preferred) to add the entry.
   - File creation: Write the file.

7. On Skip: log warning, continue to next step (the migration's final outcome
   will be marked partial).

8. On Abort: invoke each applied step's **Rollback** clause in reverse order.
   Then exit with the partial outcome.

After all steps in a migration succeed (or are intentionally skipped):

1. Run the migration's `## Post-checks` block.
2. If post-checks pass: bump `version` in the project's
   `.claude/skills/agentic-apps-workflow/SKILL.md` frontmatter to the
   migration's `to_version`. (This is a separate write from any of the
   steps — the version field is the migration runtime's record, not the
   migration content's responsibility.)
3. Commit atomically:
   ```bash
   git add -A
   git commit -m "chore: migrate AgenticApps workflow to v{TO_VERSION} (migration {ID})"
   ```
   The commit message includes the migration ID for auditability.

If `--dry-run`, do NOT bump the version field and do NOT commit.

## Step 6: Post-flight summary

Print a structured summary:

```
Update complete.

Migrations applied:
  ✅ 0001 (1.2.0 → 1.3.0): Wire Go skills + impeccable + database-sentinel
  ⚠️  0002 (1.3.0 → 1.4.0): Partial — step 4 skipped (user chose Skip)
  ⏭️  0003 (1.4.0 → 1.5.0): Skipped (required skill not installed)

Final installed version: 1.4.0 (1 migration partial; 1 skipped)

Next steps:
  - If any step was skipped: re-run /update-agenticapps-workflow when ready
  - If touching CLAUDE.md: re-run AgentLinter to confirm Position Risk is OK
```

## Failure modes

| Failure | Behavior |
|---|---|
| `.claude/skills/agentic-apps-workflow/SKILL.md` missing | Error in Step 1; suggest `/setup-agenticapps-workflow`; exit 1 |
| Version field missing from skill frontmatter | Error in Step 1; suggest `--from V` flag; exit 1 |
| No migrations directory | Error in Step 2; the workflow scaffolder repo is corrupt or out-of-date; suggest `git pull` on the scaffolder; exit 1 |
| Pre-flight fails (e.g. skill missing) | Pause for user input; do not auto-install; resume on retry |
| Step pre-condition fails | Stop migration mid-flight; user chooses fix-and-retry, skip, or abort |
| Step apply fails (e.g. file is read-only) | Stop migration; user chooses retry, skip, or abort (rollback applied steps) |
| Vendored-file divergence (local copy differs from canonical) | Step 3 detects via byte-compare; present 3-way pick (Replace / Keep / Vendor-local). Default to Keep. Migration proceeds based on user choice; outcome reflected in summary. |
| Inlined-block extraction ambiguous (migration 0009 Step 4) | Step prompts user with the extraction range and a "skip" option. If user skips, migration completes with partial outcome; CLAUDE.md keeps the inline duplication; vendored file is still in place. Re-runnable. |
| Post-check fails | Migration marked partial; version field NOT bumped; user warned; commit still happens with the qualifier "partial" in the message |

## Idempotency guarantee

Running this skill twice in a row on the same project produces:

- First run: applies all pending migrations (each step's idempotency check
  returns non-zero → applies → records).
- Second run: every step's idempotency check returns 0 → all steps skipped
  → "Up to date" message → exit 0.

There is no scenario where a re-run partially re-applies a migration and
breaks the project state. This is the contract; migrations that violate it
(no idempotency check, or a check that doesn't actually verify the apply)
are defective and must be fixed in the migration file, not worked around in
this skill.

## Reference: related skills

- `setup-agenticapps-workflow` — bootstrap a fresh project; applies all
  migrations from baseline forward.
- `agentic-apps-workflow` — the workflow itself; this skill upgrades the
  project's local copy of it.
