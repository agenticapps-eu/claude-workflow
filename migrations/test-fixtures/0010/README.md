# Migration 0010 — test fixtures

Hand-built fixtures for `migrations/0010-post-process-gsd-sections.md`.
The harness `migrations/run-tests.sh` reads them via the
`test_migration_0010` stanza.

Unlike migrations 0001 (extracted from git refs) and 0009 (hand-built
synthetic), 0010's fixtures pair an **input** `CLAUDE.md` with an
**expected** golden `expected/CLAUDE.md`. The harness runs the
post-processor script against the input and `diff`s the result against
the expected golden. Byte-for-byte match required.

## Scenarios

| Directory | Input shape | Expected outcome |
|---|---|---|
| `fresh/` | No GSD markers, plain content | No-op (output == input) |
| `inlined-7-sections/` | All 7 marker blocks inlined (project, stack, conventions, architecture, skills, workflow, profile). Source files exist under `.planning/`. | Each block replaced by self-closing form + heading + reference link. `workflow` collapses to heading-only because `.claude/claude-md/workflow.md` exists. `profile` collapses to heading-only because no `source:` attribute. |
| `inlined-source-missing/` | One block (`project`) references `source:NONEXISTENT.md`. Other sources exist. | NONEXISTENT block PRESERVED unchanged. Others normalized. |
| `with-0009-vendored/` | Post-0009 state: 5-line reference to `.claude/claude-md/workflow.md` + one inlined `project` marker block. | 0009 reference untouched. `project` marker normalized. |
| `cparx-shape/` | Replica of `cparx/CLAUDE.md` (post-0009 state — workflow block already vendored). All 6 remaining marker blocks inlined. | All 6 marker blocks normalized. Final line count ≤ 200L. |

## Layout per scenario

```
<scenario>/
├── CLAUDE.md                       (input — script reads this)
├── .planning/
│   ├── PROJECT.md                  (touched empty — script checks for existence)
│   └── codebase/
│       ├── STACK.md
│       ├── CONVENTIONS.md
│       └── ARCHITECTURE.md
├── .claude/
│   ├── claude-md/
│   │   └── workflow.md             (touched empty — present only when 0009 has applied)
│   └── skills/                     (mkdir — script checks for existence)
└── expected/
    └── CLAUDE.md                   (golden — harness diffs script output against this)
```

The harness copies the entire scenario directory into a temp dir before
running the script, so the fixture stays read-only. The script is
invoked with the temp dir as $CWD; it resolves source paths
relative to that CWD.

## What this DOES cover

- Marker detection + replacement (regex correctness)
- Source-existence safety (preserve when missing)
- Self-closing form idempotency (script is no-op on already-normalized markers)
- Interaction with migration 0009 (vendored block is untouched)
- Empirical line-count target (cparx-shape drops to ≤ 200L)

## What this does NOT cover

- The migration runtime's apply step (the agent-driven prompts, git
  diff captures, etc.). These are markdown prose interpreted by the
  agent — not directly testable from bash. End-to-end validation
  requires running the migration through `/update-agenticapps-workflow`
  against a real project (e.g. `factiv/cparx` once 1.9.0 ships).
- The Claude Code hook lifecycle (PostToolUse firing on actual Edit/
  Write tool calls). The harness verifies the hook script behavior in
  isolation; the registration is a structural check on the JSON of
  `.claude/settings.json`.
