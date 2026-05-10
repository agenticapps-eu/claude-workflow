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

## Outputs

- `.scan-report.md` at the project root (overwritten if it exists).
- Console summary: counts by confidence + spec citation.
- Exit silently — never modify source files.

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
stack detected" and exit.

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
3. Walk the source tree under the module root using `Glob` for the
   relevant file patterns (`*.ts`, `*.tsx`, `*.go`, etc., excluding
   tests and generated code).
4. For each file, apply the detector patterns from `detectors.md` and
   classify each finding into one of:
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

- Project name (from the instruction file or directory name).
- Spec version checked (`0.2.1`).
- Date (today's date).
- Detected stacks list.
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
Scan complete. Spec: 0.2.1. Stacks: <list>.
Conformant:    <N>
High gaps:     <N>  (apply with `scan-apply --confidence high`)
Medium:        <N>  (review)
Low:           <N>  (suggestions)
```

If high-confidence gaps > 0, also print:
"See `.scan-report.md` for details. Run `scan-apply` to auto-fix the
high-confidence gaps."

## Important rules

- **Never modify source code in this subcommand.** The user runs scan
  to learn the state, not to change it.
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

## Verification before exiting

Before exiting:

1. Confirm `.scan-report.md` exists at project root.
2. Confirm the report renders cleanly (no unfilled `{{...}}` templates,
   no dangling section headers without content).
3. Confirm zero source files were modified — run a mental diff over
   what tools you called (only Read, Grep, Glob, and a single Write to
   `.scan-report.md`).
