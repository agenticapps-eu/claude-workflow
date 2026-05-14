# Migration 0009 — test fixtures

Hand-built fixtures for `migrations/0009-vendor-claude-md-sections.md`.
The harness `migrations/run-tests.sh` reads them via the
`test_migration_0009` stanza.

Unlike migration 0001's fixtures (extracted from git refs at run time),
0009's scenarios cannot be derived from claude-workflow's own git history
— the "pre-existing inlined block" state is what consumer projects (cparx,
fx-signal-agent) look like *as of today*, not what claude-workflow itself
ever shipped. Hand-built synthetic fixtures are the right tool.

## Scenarios

| Directory | Project version | Vendored file | CLAUDE.md state | Migration outcome |
|---|---|---|---|---|
| `before-fresh/` | 1.6.0 | absent | small project-only content, no inlined block | Steps 1, 2, 3, 5 apply; Step 4 idempotency = applied (nothing to remove) |
| `before-inlined-pristine/` | 1.6.0 | absent | contains canonical inlined workflow block | All 5 steps apply; Step 4 prompts user (canonical match → safe-to-remove) |
| `before-inlined-customised/` | 1.6.0 | absent | contains customised inlined workflow block | All 5 steps apply; Step 4 prompts user with diff (3-way pick) |
| `after-vendored/` | 1.8.0 | present (canonical) | reference link only | All idempotency checks return 0; migration is no-op |
| `after-idempotent/` | 1.8.0 | present (canonical) | reference link only | Same as above; verifies a *second* run after migration is also no-op |

## Layout per scenario

Each directory contains the minimum files the migration's idempotency
checks read:

```
<scenario>/
├── CLAUDE.md
├── .claude/
│   ├── claude-md/                    (only in after-* scenarios)
│   │   └── workflow.md
│   └── skills/
│       └── agentic-apps-workflow/
│           └── SKILL.md              (synthetic — has version field, nothing else)
```

The harness copies a scenario into a temp directory before running
assertions. Fixtures themselves are read-only.

## What this does NOT cover

- The **apply** step (file mutation behavior). The migration's apply
  blocks are markdown prose interpreted by the agent at execution time,
  not bash scripts the harness can run. End-to-end validation requires
  running the migration through `/update-agenticapps-workflow` against a
  real project (e.g. `factiv/fx-signal-agent`).
- The **3-way pick** UX in Step 4 / divergence detection. Same reason —
  agent-driven.

The harness verifies the contract that the migration runtime relies on:
**idempotency checks must correctly classify before vs after states.**
That's the most common defect surface (bad anchor strings) and the one
bash can verify cheaply.
