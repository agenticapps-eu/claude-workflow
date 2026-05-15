# `scan` subcommand procedure

You are running the `scan` subcommand of the `add-observability` skill
against the user's current project. Your job is to produce a
**confidence-ranked report** of where the project does and does not
conform to AgenticApps core spec §10.4 (mandatory instrumentation
points). You MUST NOT modify any source code in this run — that's the
`scan-apply` subcommand's job.

## Inputs

- **Project root**: the working directory (the user's open project).
- **Severity filter** (optional, default `all`): `high`, `medium`,
  `low`, or `all`. Findings below the requested severity are still
  counted in the summary but not enumerated.
- **`--since-commit <ref>`** (optional, default unset, **v0.3.0 §10.9.1**):
  resolves `<ref>` to a 40-char commit SHA and limits the walk to files
  changed between `<ref>` and HEAD (delta scan). Incompatible with
  `--update-baseline` — pick one or neither.
- **`--update-baseline`** (optional, default false, **v0.3.0 §10.9.2**):
  after the scan, write `.observability/baseline.json` reflecting the
  full-scan state. Full-scan only (rejected if combined with
  `--since-commit`).

## Outputs

- `.scan-report.md` at the project root (overwritten if it exists).
  Frontmatter declares `scope: full | delta`; delta reports also
  include `since_commit`, `head_commit`, and `files_walked`.
- `.observability/baseline.json` (only when `--update-baseline` set,
  per spec §10.9.2). Canonical path; never overridden by this skill.
- `.observability/delta.json` (only when `--since-commit` set, per
  spec §10.9.1). Emitted **unconditionally** whenever delta scope is
  requested — even when the walk is empty. This is the machine-readable
  summary the CI gate diffs against the baseline.
- Console summary: counts by confidence + spec citation.
- Exit silently — never modify source code files (the
  `.observability/` artefacts are scaffolder-written outputs, not
  source code).

## Procedure

### Phase 1 — Detect stacks

Read `./templates/*/meta.yaml` (relative to this skill) to enumerate
known stacks and their `path_root` manifests. For each stack:

1. Use `Glob` to find all instances of `path_root` in the project tree
   (excluding `node_modules/`, `.git/`, `vendor/`, `dist/`, `build/`,
   `.claude/worktrees/`).
2. For each candidate manifest, evaluate the stack's `detection.must`
   and `detection.any_of` rules using `Read` / `Grep`.
3. The manifest's directory is a confirmed module root for the stack.

A project may match multiple stacks (e.g. cparx matches `go-fly-http`
at `backend/go.mod` AND `ts-react-vite` at `frontend/package.json`).
Treat each match independently.

If zero stacks match, write a `.scan-report.md` saying "no AgenticApps
stack detected" and exit. If `--since-commit` was set, ALSO emit
`.observability/delta.json` with empty `files_walked` and zero counts,
per Phase 8 — the machine-readable summary is unconditional.

### Phase 1.5 — Resolve scope (delta vs full, added v0.3.0 §10.9.1)

Determine whether this is a **full** scan or a **delta** scan, and
compute the file-scope set the subsequent phases walk.

1. If `--since-commit` was NOT provided, this is a **full scan**.
   - `scope = "full"`
   - The file-scope is "all files matching each detected stack's
     `target` patterns under that stack's module root" (the same set
     that Phase 3 walked in v0.2.x).
   - Continue to Phase 2.

2. If `--since-commit <ref>` was provided, this is a **delta scan**.

   a. Reject if `--update-baseline` was also passed:
      ```
      ERROR: --since-commit and --update-baseline are mutually exclusive.
      Use one, neither, or chain two invocations.
      ```

   b. Resolve `<ref>` to a 40-char commit SHA:
      ```bash
      since_commit=$(git rev-parse --verify "${ref}^{commit}" 2>/dev/null)
      ```
      If empty, error out: `ERROR: --since-commit ref "{ref}" does not resolve to a commit. Available branches: <git branch --all | head -5>`.

   c. Resolve HEAD:
      ```bash
      head_commit=$(git rev-parse HEAD)
      ```

   d. Compute the diff scope using **triple-dot** semantics:
      ```bash
      git diff --name-only "${since_commit}...HEAD"
      ```
      Triple-dot returns files changed in HEAD's branch relative to
      the merge-base with `<ref>`, which is the spec-intended "what
      does this PR add" semantic. Two-dot would also include changes
      on the base branch since merge-base, which is the wrong question
      for a CI gate.

   e. Set:
      - `scope = "delta"`
      - `since_commit = <40-char sha>`
      - `head_commit = <40-char sha>`
      - `files_walked = <list of paths from step d, possibly empty>`

   f. **Do NOT early-exit on an empty `files_walked`.** Empty delta
      scope is a valid state — Phase 3 simply iterates zero files,
      Phase 5 emits a report banner reading "0 files changed", and
      Phase 8 emits `delta.json` with empty `files_walked` and zero
      counts. The CI gate reads `delta.json` regardless of whether the
      delta is empty.

3. Pass `scope`, `since_commit`, `head_commit`, and `files_walked`
   forward to subsequent phases.

### Phase 2 — Read project metadata

Read the project's instruction file (`CLAUDE.md` for Claude Code,
`AGENTS.md` for pi/codex hosts, or whichever exists at the project
root). Look for a top-level `## Observability` heading with an
`observability:` YAML block (per spec §10.8).

- If present and `spec_version` is `0.2.x`: the project has run `init`
  at least once. The scan validates all four checklist items.
- If absent: the project has not yet adopted the spec. The scan still
  runs, but every C1-C4 finding is reported as "needs init first" with
  a top-of-report banner.

### Phase 3 — Walk each stack

For each detected stack/module-root pair:

1. Read `./scan/checklist.md` to load the C1-C4 detection rules.
2. Read `./scan/detectors.md` for the language-specific patterns used
   by each rule.
3. Walk the **file-scope set** from Phase 1.5:
   - For a **full scan** (`scope: full`): use `Glob` for the relevant
     file patterns (`*.ts`, `*.tsx`, `*.go`, etc., excluding tests and
     generated code) under each stack's module root.
   - For a **delta scan** (`scope: delta`): intersect Phase 1.5's
     `files_walked` with each stack's relevant patterns. A delta-scan
     `files_walked` of `["frontend/src/App.tsx", "README.md",
     "backend/cmd/api/main.go"]` walks only the two source files under
     the `ts-react-vite` and `go-fly-http` stacks; `README.md` is
     ignored because it doesn't match any stack's source patterns.
   - If the intersection is empty (delta scan; no in-scope source
     files changed): proceed without walking. Phase 5 emits a report
     declaring zero findings; Phase 8 emits `delta.json` with zero
     counts.
4. For each file in scope, apply the detector patterns from
   `detectors.md` and classify each finding into one of:
   - **conformant** — already satisfies the rule (e.g. handler calls `startSpan`).
   - **high-confidence gap** — rule clearly violated; safe to auto-fix.
   - **medium-confidence finding** — heuristic match (e.g. probable business event by name).
   - **low-confidence finding** — suggestion only.

### Phase 4 — Apply trivial-error policy

For C3 (caught errors), check the project's
`<wrapper-dir>/policy.md` for a "Trivial errors" section. Errors
matching the trivial list (`pgx.ErrNoRows`, validation failures
returning 4xx, etc.) are conformant without `captureError`; everything
else is a high-confidence gap.

If `policy.md` does not exist (project hasn't run `init`), fall back to
the default trivial list:

- `pgx.ErrNoRows` (Go)
- `sql.ErrNoRows` (Go)
- HTTP responses returning 400, 404, 422
- `context.Canceled`, `context.DeadlineExceeded`
- TypeScript: errors thrown for input validation and rethrown as 4xx

### Phase 5 — Compose the report

Read `./scan/report-template.md` and instantiate it with:

- **Report frontmatter** (new in v0.3.0):
  - `scope: full | delta` from Phase 1.5
  - For delta scans only: `since_commit`, `head_commit`, `scanned_at`
- Project name (from the instruction file or directory name).
- Spec version checked (`0.3.0`).
- Date (today's date).
- Detected stacks list.
- For delta scans only: a "delta banner" under the H1 declaring the
  file count and listing `files_walked` (or "0 files changed" if
  empty).
- Conformance summary (counts by confidence).
- Findings grouped by checklist item, ordered by file path then line number.
- A "next steps" section that names the user's options:
  `scan-apply --confidence high` to auto-apply mechanical fixes;
  manual review for medium/low; `policy.md` updates if the trivial-error
  list is incomplete.

Write the report to `.scan-report.md` at the project root (NOT inside
any module-root subdirectory — there's one report per project).

### Phase 6 — Print summary

Print a 5-line summary to the user:

```
Scan complete. Spec: 0.3.0. Stacks: <list>.
Conformant:    <N>
High gaps:     <N>  (apply with `scan-apply --confidence high`)
Medium:        <N>  (review)
Low:           <N>  (suggestions)
```

If high-confidence gaps > 0, also print:
"See `.scan-report.md` for details. Run `scan-apply` to auto-fix the
high-confidence gaps."

### Phase 7 — Update baseline (only if `--update-baseline` set, added v0.3.0 §10.9.2)

Skip this phase entirely if `--update-baseline` was NOT passed. Per
spec §10.9.2 (line 219), a regular `scan` invocation MUST NOT rewrite
the baseline file — only `--update-baseline` (manual) and `scan-apply`
success (automatic, see `scan-apply/APPLY.md` Phase 6b) do.

**Pre-conditions** (Phase 7 only):

1. `policy.md` MUST exist at the path declared by the project's
   `observability.policy` metadata field (or default
   `lib/observability/policy.md` if no metadata). If missing:
   ```
   ERROR: policy.md not found at {path}. Run `add-observability init`
   first to scaffold the wrapper + policy, then re-run with
   --update-baseline.
   ```

2. The project MUST have at least one git commit:
   ```bash
   git rev-parse HEAD >/dev/null 2>&1 || {
     echo "ERROR: project has no git commits. Commit something first."
     exit 3
   }
   ```

**Procedure**:

1. Read `./scan/baseline-template.json`.

2. Fill tokens:
   - `DATE_ISO` = `date -u +%Y-%m-%dT%H:%M:%SZ` (RFC 3339 UTC).
   - `COMMIT_SHA` = `git rev-parse HEAD` (40-char hex; **never**
     truncated, **never** the string `"working-tree"`). Uncommitted
     changes in the working tree are not reflected in the baseline —
     by design.
   - `MODULE_ROOTS` = the list of `{stack, path}` pairs from Phase 1
     detection, **sorted lexicographically by (stack, path)**.
   - `COUNTS` = the aggregation produced by Phase 5.
   - `HIGH_CONFIDENCE_GAPS_BY_CHECKLIST` = per-checklist tallies of
     high-confidence gaps (C1, C2, C3, C4).
   - `POLICY_HASH_HEX` = the lowercase hex sha256 of `policy.md`'s
     raw bytes:
     ```bash
     shasum -a 256 "$POLICY_PATH" | awk '{print $1}'
     ```
     The full `policy_hash` field is rendered as
     `"sha256:<POLICY_HASH_HEX>"`.

3. Atomic write:
   ```bash
   mkdir -p .observability
   <fill template> > .observability/baseline.json.tmp
   mv .observability/baseline.json.tmp .observability/baseline.json
   ```

4. Print: `Baseline updated: .observability/baseline.json (high-confidence gaps: <N>)`.

### Phase 8 — Write delta artefact (only if `--since-commit` set, added v0.3.0 §10.9.1)

Skip this phase entirely if `--since-commit` was NOT passed.

**Unconditional on Phase 1.5 outcome**: this phase runs even when
`files_walked` is empty. The spec's machine-readable-summary obligation
is unconditional — every delta scan emits `delta.json`.

**Procedure**:

1. Compose the delta JSON:
   ```json
   {
     "spec_version": "0.3.0",
     "scanned_at": "<RFC 3339 UTC>",
     "since_commit": "<40-char SHA from Phase 1.5>",
     "head_commit": "<40-char SHA from Phase 1.5>",
     "files_walked": [<paths from Phase 1.5; may be empty>],
     "counts": {
       "conformant": <N>,
       "high_confidence_gaps": <N>,
       "medium_confidence_findings": <N>,
       "low_confidence_findings": <N>
     },
     "high_confidence_gaps_by_checklist": {
       "C1": <N>, "C2": <N>, "C3": <N>, "C4": <N>
     }
   }
   ```

2. Atomic write:
   ```bash
   mkdir -p .observability
   <compose JSON> > .observability/delta.json.tmp
   mv .observability/delta.json.tmp .observability/delta.json
   ```

3. Print: `Delta artefact: .observability/delta.json (files walked: <N>, high-confidence gaps: <N>)`.

## Important rules

- **Never modify source code in this subcommand.** The user runs scan
  to learn the state, not to change it. (The `.observability/`
  artefacts written by Phases 7 and 8 are scaffolder outputs, not
  source code.)
- **Never delete `.scan-report.md` from a previous run before
  starting** — overwrite at the end (so a crashed scan leaves the
  previous report intact).
- **Walk inclusively**: it's better to flag a probable false-positive
  as medium-confidence than to miss a real gap. The user filters
  via `scan-apply --confidence`.
- **Respect the per-stack file ignore lists** in
  `templates/<stack-id>/meta.yaml` (`detection` and
  `target.per_function_pattern.skip`).
- **For Go projects with multiple `cmd/*/main.go`**: each main.go is
  its own entry point. Apply C1 to each.
- **For monorepos**: produce ONE report at the project root covering
  all detected stacks. Group findings by stack.
- **Delta-scan reports MUST NOT rewrite the baseline file.** Per spec
  §10.9.2 line 219, the baseline is only updated by `--update-baseline`
  (manual) or `scan-apply` success (automatic). A delta scan reads
  no baseline, writes no baseline. (Added v0.3.0.)
- **Delta scope uses `git diff --name-only <ref>...HEAD` (triple-dot).**
  This is merge-base relative — the set of files changed by HEAD's
  branch since diverging from `<ref>`. Two-dot would include changes
  on `<ref>` since merge-base, which is the wrong question for a CI
  gate. (Added v0.3.0.)
- **Empty deltas still emit `delta.json`.** The §10.9.1
  machine-readable-summary obligation is unconditional whenever
  `--since-commit` is set, regardless of whether any in-scope source
  files changed. CI gates rely on the artefact's presence. (Added
  v0.3.0.)
- **`scanned_commit` and `policy_hash` in `baseline.json` are strict
  schema fields.** `scanned_commit` is always a 40-char hex SHA from
  `git rev-parse HEAD`; never abbreviated, never the string
  "working-tree". `policy_hash` is always `sha256:<64-hex>`; never
  null, never a degraded value. Projects without `policy.md` cannot
  produce a baseline — they must run `add-observability init` first.
  (Added v0.3.0 per spec §10.9.2 lines 184-217.)

## Verification before exiting

Before exiting:

1. Confirm `.scan-report.md` exists at project root.
2. Confirm the report renders cleanly (no unfilled `{{...}}` templates,
   no dangling section headers without content).
3. If `--update-baseline` was set: confirm `.observability/baseline.json`
   exists and parses (`jq -e '.spec_version == "0.3.0"' .observability/baseline.json`).
4. If `--since-commit` was set: confirm `.observability/delta.json`
   exists and parses (`jq -e '.spec_version == "0.3.0"' .observability/delta.json`).
5. Confirm zero source files were modified — run a mental diff over
   what tools you called (only Read, Grep, Glob, and Writes to
   `.scan-report.md` and (conditionally) `.observability/*.json`).
