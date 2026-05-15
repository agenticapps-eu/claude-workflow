# Scan report template

The `scan` subcommand fills this template into `.scan-report.md` at the
project root. Substitution tokens use double-curly: `{{...}}`.

---

```markdown
---
scope: {{SCOPE}}
since_commit: {{SINCE_COMMIT}}
head_commit: {{HEAD_COMMIT}}
scanned_at: {{DATE_ISO}}
---

# Observability scan report — {{PROJECT_NAME}}

{{DELTA_BANNER}}

**Spec version checked**: {{SPEC_VERSION}}
**Stacks detected**: {{STACK_LIST}}
**Module roots**:
{{MODULE_ROOT_LIST}}
**Date**: {{DATE_ISO}}
**Generator**: add-observability skill v{{SKILL_VERSION}}

## Conformance summary

| Status | Count | Action |
|---|---|---|
| Conformant | {{COUNT_CONFORMANT}} | — |
| High-confidence gaps | {{COUNT_HIGH}} | `scan-apply --confidence high` (recommended) |
| Medium-confidence findings | {{COUNT_MEDIUM}} | Manual review |
| Low-confidence findings | {{COUNT_LOW}} | Suggestions only |

{{INIT_BANNER_IF_PRESENT}}

## High-confidence gaps

{{HIGH_CONFIDENCE_FINDINGS}}

## Medium-confidence findings (review)

{{MEDIUM_CONFIDENCE_FINDINGS}}

## Low-confidence findings (suggestions)

{{LOW_CONFIDENCE_FINDINGS}}

## Conformant sites

{{CONFORMANT_SUMMARY}}

## Next steps

{{NEXT_STEPS}}

---

*Generated {{DATE_ISO}} by `add-observability` skill against AgenticApps spec §10 v{{SPEC_VERSION}}. Re-run scan to refresh; pass `--severity high` to limit output to high-confidence gaps only.*
```

---

## Section content rules

### Frontmatter fields (added v0.3.0 §10.9.1)

- `{{SCOPE}}` — literal string `full` or `delta`.
- `{{SINCE_COMMIT}}` — for `scope: delta`, the 40-char SHA `<ref>`
  resolved to in SCAN.md Phase 1.5. For `scope: full`, omit this line
  from the frontmatter (do NOT render with an empty value).
- `{{HEAD_COMMIT}}` — for `scope: delta`, the 40-char SHA from
  `git rev-parse HEAD`. For `scope: full`, omit.
- `{{DATE_ISO}}` — RFC 3339 UTC timestamp (e.g. `2026-05-15T09:30:00Z`).

When `scope: full`, the frontmatter contains only `scope` and
`scanned_at`. When `scope: delta`, all four fields are present.

### `{{DELTA_BANNER}}` (added v0.3.0)

- If `scope: full`: render as empty (no banner at all).
- If `scope: delta` AND `files_walked` is non-empty:
  ```markdown
  > **Delta scan** — {{FILE_COUNT}} file(s) changed since `{{SINCE_COMMIT_SHORT}}`.
  > Findings below are the delta only. Run `scan --update-baseline` for the full baseline.
  >
  > Files walked:
  > ```
  > {{FILE_LIST_NEWLINE_JOINED}}
  > ```
  ```
  where `SINCE_COMMIT_SHORT` is the 7-char abbreviation of
  `SINCE_COMMIT` and `FILE_LIST_NEWLINE_JOINED` is the list of files
  joined by `\n`.

- If `scope: delta` AND `files_walked` is empty:
  ```markdown
  > **Delta scan** — 0 files changed since `{{SINCE_COMMIT_SHORT}}`. No findings to report.
  ```

### `{{INIT_BANNER_IF_PRESENT}}`

- If the project's instruction file does NOT contain an
  `observability:` metadata block (i.e. the project hasn't run `init`):

  ```markdown
  > **⚠️ This project has not run `init` yet.** All gaps below are
  > expected — they will be resolved when you run `add-observability init`.
  > Run init first, then re-scan.
  ```

- If the metadata block IS present, render this section as empty.

### `{{HIGH_CONFIDENCE_FINDINGS}}`, `{{MEDIUM_...}}`, `{{LOW_...}}`

For each confidence bucket, group by checklist item (C1, C2, C3, C4)
in that order. For each finding, render:

```markdown
### {{CHECKLIST_ID}} — {{CHECKLIST_TITLE}}

- `{{file_path}}:{{line_number}}` — {{one_line_description}}
  Proposed insertion:
  ```{{language}}
  {{code_diff}}
  ```
```

If the same checklist has multiple findings, list them all under one
heading.

If a confidence bucket has zero findings, render the heading with a
single line: `*(none)*`.

### `{{CONFORMANT_SUMMARY}}`

Aggregate counts per checklist item:

```markdown
- C1 (handler entry): {{N}} of {{TOTAL}} sites instrumented.
- C2 (outbound calls): {{N}} of {{TOTAL}} call sites propagate `traceparent`.
- C3 (caught errors): {{N}} of {{TOTAL}} non-trivial error sites call `captureError`.
- C4 (business events): {{N}} of {{TOTAL}} probable event sites emit `logEvent`.
```

Do NOT enumerate every conformant site — that bloats the report. Add a
note: "Run with `--verbose` to list every conformant site."

### `{{NEXT_STEPS}}`

A short prose section with conditional contents:

- If `init_banner_if_present` was triggered:
  > Run `add-observability init` to scaffold the wrapper and middleware. After init, re-run `scan` to validate the post-init state.

- Else if `COUNT_HIGH > 0`:
  > Run `add-observability scan-apply --confidence high` to auto-apply the {{COUNT_HIGH}} high-confidence fixes with per-file consent. Each insertion will be shown as a diff before writing.

- Else if `COUNT_MEDIUM > 0`:
  > {{COUNT_MEDIUM}} medium-confidence findings need human review. They are heuristic matches — the scanner identified probable business events by naming patterns, but only you know whether each function is a state-changing event worth recording. Edit the file, add `LogEvent` calls where appropriate, then re-scan.

- Else if `COUNT_LOW > 0`:
  > Project is conformant on the high and medium tracks. {{COUNT_LOW}} low-confidence suggestions remain (typically deferred-to-v0.3.0 items like database query tracing). Review at your leisure.

- Else:
  > **Conformance complete.** All four mandatory instrumentation points (§10.4) are satisfied across all detected stacks. Re-run scan periodically as the codebase grows.

---

## Notes for the agent producing the report

- Use the literal token `*(none)*` for empty buckets (italic, single
  word) — do NOT omit the heading; consistency aids diffing across
  scans.
- File paths are relative to the project root, NOT the module root.
  This way the report is self-contained even in monorepos.
- Code-diff blocks use the file's language for syntax highlighting
  (`go`, `ts`, `tsx`).
- Keep findings ordered by file path (alphabetical), then by line
  number. This makes scan-vs-scan diffs trivially readable.
