# `scan-apply` subcommand procedure

You are running the `scan-apply` subcommand of the `add-observability`
skill. Your job is to apply high-confidence findings from
`.scan-report.md` to the user's source code, **with explicit per-file
or per-batch consent**. You MUST NOT auto-apply anything. Per spec
§10.7 ("Apply only with consent"), an apply that bypasses confirmation
is non-conformant.

## Inputs

- **Project root**: the working directory.
- **Severity filter** (optional, default `high`): `high`, `medium`,
  `low`. The default applies only high-confidence findings.
- **Mode** (optional, default `per-file`):
  - `per-file` — show each affected file's full set of diffs together,
    prompt apply/skip/quit per file.
  - `batch` — group diffs by checklist item across files, prompt per
    checklist group.

## Outputs

- Source files modified per approved insertions.
- `.scan-report.md` updated to reflect post-apply state.
- Console summary: applied N / skipped M / failed K / total P.

## Procedure

### Phase 1 — Validate the scan report

1. Read `.scan-report.md` from the project root.
   - If it doesn't exist, exit with: "No scan report found. Run
     `add-observability scan` first."
   - If it exists but is older than 24 hours OR the project has new
     commits since the report's date, warn the user:
     "Report is stale (last scan: {{DATE}}). Re-run scan? [Y/n]" — if
     `n`, proceed with the existing report; if `Y` or default, abort
     and ask the user to run `scan` again.

2. Parse the report. Extract findings into a structured list:
   ```
   { id, checklist, file, line, description, language, code_diff,
     confidence, status }
   ```
   The confidence buckets are read from the report headings
   (`## High-confidence gaps`, `## Medium-confidence findings`, etc.).

3. Filter by `--severity`. The default `high` keeps only findings under
   `## High-confidence gaps`.

### Phase 2 — Group by mode

- **per-file mode**: group findings by `file`. Within each file, sort
  by line number. For files with multiple findings, plan all diffs
  together and present as one consent prompt.

- **batch mode**: group findings by `checklist`. For each checklist
  item (C1, C2, C3, C4), gather findings across files and present
  together.

### Phase 3 — Resolve each finding to a concrete Edit

For each finding:

1. **Read** the target file using the Read tool.
2. **Locate the insertion point**. The scan report's `code_diff` block
   shows the proposed code. Construct the Edit:
   - `old_string`: the current line(s) at the insertion point WITHOUT
     the proposed insertion. Capture enough context (typically 3-5
     surrounding lines) to make `old_string` unique in the file.
   - `new_string`: same lines WITH the proposed insertion in place.
3. **Idempotency check**: grep the file for a unique marker from the
   proposed insertion (e.g. `observability.Middleware` for a C1 fix).
   If already present, mark the finding `status: skipped (already
   applied)` and continue — no Edit needed.

4. **Stale-context detection**: if the surrounding context in the file
   has changed since the scan (the scan saw lines A-B-C; the file now
   shows A-D-C), `old_string` won't match. Mark
   `status: stale (re-scan)` and continue. Don't try to repair stale
   context — that's a re-scan job.

If a finding can't be resolved (file deleted, syntax broken), mark
`status: failed` with the reason. Continue with the next finding;
never abort the whole apply because of one bad finding.

### Phase 4 — Present diffs and get consent

For each group (per-file or per-batch):

1. Print a clear header:
   ```
   ─── File: backend/cmd/api/main.go (3 high-confidence gaps) ───
   ```

2. For each finding in the group, print:
   - Finding ID and checklist (`C1.1`, `C2.3`, etc.).
   - One-line description.
   - The diff in unified-diff format (use `+` and `-` markers).
   - The literal Edit pair (old_string / new_string) that will be
     issued — so the user can see exactly what changes.

3. Print the prompt:
   ```
   Apply these N changes? [a]pply / [s]kip / [q]uit
   ```

4. **Wait for the user's response in the chat.** Do NOT proceed
   without an explicit reply. Acceptable replies:
   - `a`, `apply`, `yes`, `y` — apply this group.
   - `s`, `skip`, `no`, `n` — skip this group; continue with the next.
   - `q`, `quit`, `cancel` — abort the apply session entirely.
   - Anything else — re-prompt with the same options.

   "Apply only with consent" means the consent must come from the user
   directly in the chat. Skill-internal heuristics ("looks safe") do
   NOT satisfy this requirement.

### Phase 5 — Apply approved Edits

For each approved finding:

1. Issue the Edit via the Edit tool with the resolved `old_string` and
   `new_string`.
2. If the Edit succeeds, mark `status: applied`.
3. If the Edit fails (typically: `old_string` not found because the
   file changed between Phase 3's read and now), mark
   `status: failed (Edit error: ...)` with the actual error message.
4. After each file's group is fully processed, run an optional sanity
   check — see Phase 7.

### Phase 6 — Update `.scan-report.md`

Rewrite `.scan-report.md` reflecting the post-apply state:

1. Re-classify each previously-listed finding by its new `status`:
   - `applied` → moves from high-confidence gaps to "Applied this run".
   - `stale (re-scan)` → moves to "Stale — needs re-scan".
   - `failed` → moves to "Failed — manual review".
   - `skipped (already applied)` → moves to "Conformant sites".
   - Unprocessed findings (e.g. medium/low when running `--severity high`)
     remain in their original sections.

2. Add a top-of-report banner:
   ```
   > Last apply run: {{DATE_ISO}} — applied {{N}}, skipped {{M}},
   > failed {{K}} of {{TOTAL}} high-confidence gaps. Re-run scan to
   > revalidate.
   ```

3. Write the rewritten report to `.scan-report.md`.

### Phase 7 — Optional verification

For each language touched in this apply run, run the language's
fast-feedback check (compile/typecheck), if available in the
environment:

- **Go**: `go build ./...` — must succeed. If it fails, the apply has
  introduced a compile error. Print the error and offer to revert via
  `git checkout -- <file>` for each modified file.
- **TypeScript**: `tsc --noEmit -p .` — same.
- **Deno**: `deno check **/*.ts` — same.

This is a post-condition check, not a gate before applying. The user
sees their files modified, then sees the build status. They can revert
via git if desired.

If the language tooling isn't available in the environment, skip this
phase — the user runs verification themselves.

### Phase 8 — Print summary

```
scan-apply complete.
Applied:    {{N}}
Skipped:    {{M}}  ({{M_already_applied}} already applied, {{M_user_skipped}} declined)
Failed:     {{K}}  (see .scan-report.md "Failed" section)
Stale:      {{S}}  (re-run `add-observability scan`)
```

If `K > 0` or `S > 0`, exit with a clear next-action recommendation.

## Important rules

- **Consent is per-group, not per-finding.** A `--mode batch` run that
  applies 30 fixes across 12 files needs 4 user prompts (one per
  checklist), not 30. But the user MUST see the full diff for every
  finding in the group before consenting.

- **The Edit tool is the safety net.** Its content-matching behavior
  prevents accidental modification when the file has changed. Don't
  bypass it with Write — Write would clobber concurrent edits.

- **Never auto-apply across all files in a single prompt.** A single
  global "[a]pply all" option would defeat the consent model. The
  modes are `per-file` and `batch` — both require multiple prompts
  for multiple groups.

- **Re-runs are idempotent.** If a previous apply succeeded, a second
  run with the same report sees `status: skipped (already applied)`
  for those findings and applies nothing. This is correct; it
  protects the user against accidental double-application.

- **Failures don't abort the run.** A single finding's failure is
  reported and skipped; the rest of the run continues. The user's
  consent for the group covered the intent ("apply these"), so other
  findings in the group should still be attempted.

## What this subcommand does NOT do

- Does NOT auto-fix medium-confidence findings without explicit
  `--severity medium` opt-in. Heuristic findings need human review.
- Does NOT modify `policy.md` or `lib/observability/` files. Those are
  init-subcommand outputs; if the wrapper itself needs updating, run
  `init --force` (a separate manual step).
- Does NOT run `git commit`. Modified files stay in the working tree;
  the user reviews and commits via their normal workflow (typically a
  feature branch + PR per cparx CLAUDE.md).
- Does NOT delete files. Insertions only.
