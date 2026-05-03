# ADR-0013: Migration framework for AgenticApps workflow upgrades

**Status:** Accepted
**Date:** 2026-05-03
**Linear:** —
**Phase:** Phase 4 of `feat/wire-go-impeccable-database-sentinel`

## Context

Before this work, the AgenticApps workflow scaffolder shipped one path —
`/setup-agenticapps-workflow` — that copied templates into a fresh project.
There was no upgrade path: when the scaffolder shipped a new feature
(e.g. a new hook), every existing project either:

1. Re-ran setup (destructive — overwrote project-customized config), or
2. Manually patched in the new feature (drift across projects), or
3. Stayed on the old version forever (latent debt).

This phase wires three new gates simultaneously (Go routing, impeccable,
database-sentinel). Multiplied across N existing AgenticApps projects, the
"manually patch in" cost dominates. A migration framework was the only way
to ship this delta non-destructively at scale.

A second motivation: the prompt for this work itself called out a "two
divergent code paths" bug — `setup` and any future `update` skill would
maintain duplicate logic for "what does v1.3.0 look like on disk." The
fix is to model both as "apply migrations N₁..N_k" against different
starting states (`unknown` for setup, the installed version for update).

## Decision

Adopt a **versioned migration framework** modeled on Rails / Sequelize
migrations, adapted for markdown-skill content rather than database schemas.

### Architecture

```
~/.claude/skills/agenticapps-workflow/
├── migrations/
│   ├── README.md                                # format spec
│   ├── 0000-baseline.md                         # fresh-project starting state
│   ├── 0001-go-impeccable-database-sentinel.md  # this work
│   ├── 0002-...                                 # future
│   ├── test-fixtures/                           # before/after snapshots
│   └── run-tests.sh                             # fixture-based test runner
├── setup/SKILL.md                               # applies 0000+ in order
├── update/SKILL.md                              # applies pending migrations
└── skill/SKILL.md                               # the workflow itself
                                                 # frontmatter contains
                                                 # `version: X.Y.Z`
```

### Migration file format

Each migration is a markdown file with:

- **Frontmatter:** `id`, `slug`, `title`, `from_version`, `to_version`,
  `applies_to`, `requires` (external skill deps), `optional_for`
  (conditional steps).
- **Pre-flight:** shell block that checks the project is in the expected
  state.
- **Steps:** each step has `Idempotency check`, `Pre-condition`, `Apply`
  (the patch text), `Rollback`.
- **Post-checks:** validation queries.
- **Skip cases:** documented exits.

### Where the installed version lives

In the project's `.claude/skills/agentic-apps-workflow/SKILL.md`
frontmatter `version:` field. Both `setup` and `update` write this; both
read it.

### Idempotency, atomicity, dry-run

- **Idempotency:** every step ships with a `grep -q` / `jq -e` / `test -f`
  check that returns 0 if applied. Re-running is safe and produces "all
  skipped" output.
- **Atomicity:** if step N fails, the user is prompted to retry, skip
  with warning, or rollback steps 1..N-1 via their `Rollback` clauses.
- **Dry-run:** `--dry-run` prints diffs without writing or committing.
  Default interactive flow is dry-run-then-confirm.

### Setup ⊕ update unification

Migration `0000-baseline.md` codifies the v1.2.0 starting state as a
sequence of file-creation steps. Setup applies migrations from `0000`
forward; update applies migrations from the project's installed version
forward. Same migration files, same runtime, same on-disk outcome.

## Alternatives Rejected

- **Re-run setup destructively on every upgrade.** Rejected — destroys
  project-specific customization (workflow-config.md placeholders,
  edited CLAUDE.md sections). Trades correctness for engineering
  expedience. The whole point of a workflow scaffolder is that the
  project is allowed to diverge after install.
- **Per-feature manual patch instructions in CHANGELOG.md.** Rejected —
  multiplies linearly with N projects × M features. The patch instructions
  are exactly the migration content; codifying them as a runnable file
  costs nothing extra and gains idempotency, validation, and rollback.
- **Schema migration via `git diff` + `git apply`.** Rejected — git
  patches are positional (line numbers), not anchored. Project files
  drift across the line numbers between the scaffolder version and the
  project install. The migration framework's `grep -q` / `jq -e` checks
  are anchored on content, which survives drift.
- **Rails/Sequelize-style numeric IDs without semver `to_version`.**
  Rejected — sequential IDs alone don't tell the user "what version am I
  on now". Pairing sequential IDs with `to_version` gets both: easy
  ordering and human-readable version state.
- **Use the existing GSD framework's migration concepts.** Rejected —
  GSD operates on phases (work units), not on the workflow itself. A
  workflow upgrade is meta-work that GSD's phase model doesn't fit.
- **Defer the framework; ship Phase 1-3 patches as a CHANGELOG with
  manual instructions.** Rejected — the user's Q4 answer chose Full
  Phase 4 explicitly. The architectural payoff (no future migrations
  ever require manual instructions) compounds; deferring it just makes
  the next migration also use ad-hoc patches.
- **Single idempotent setup skill with convergence logic.** Rejected —
  this is essentially what v1.2.0 setup was, plus branching to handle
  every "if installed shape is X, transform to Y" path. Each new feature
  balloons the skill's conditional logic; the skill becomes a god-object
  that has to know every historical state and every transition. Migration
  files make each delta self-contained, individually reviewable, and
  individually testable. The cost (more files) is dominated by the win
  (each migration is local reasoning, not a strand of a growing decision
  tree).

## Consequences

**Positive:**
- Existing AgenticApps projects can upgrade non-destructively in one
  command: `/update-agenticapps-workflow`. Per-step diff + confirm
  preserves user agency at each touch point.
- Setup and update share one runtime — no divergent code paths to keep
  in sync.
- Future features ship as one new migration file. The discipline is
  encoded once (in `migrations/README.md`) and inherited automatically.
- Test fixtures + `run-tests.sh` give every migration a reproducible
  validation gate before merge.
- `--dry-run` makes the upgrade UX safe by default — users see exactly
  what will change before any write.

**Negative:**
- Adds significant scaffolding upfront (this phase): the framework spec,
  the runtime in two skills, the format documentation, two migration
  files, the fixture harness, this ADR. ~1500 lines of new content for
  what looks externally like "wire three skills." The payoff is on the
  next 5 migrations; if the project never ships another migration, this
  was over-engineering.
- The migration runtime is markdown-skill prose, not executable code.
  Idempotency checks are shell snippets the agent runs; the apply step
  is markdown the agent interprets and writes. This is fragile if the
  agent's interpretation of "apply this patch" drifts. Mitigation: every
  patch is shown as a literal code block (no abstract description); the
  test fixture harness verifies the on-disk outcome end-to-end.
- The framework adds one indirection: when shipping a new feature, the
  workflow scaffolder author writes both the templates AND a migration
  file. v1.2.0's "edit the templates and ship" is now "edit the
  templates, write a migration that brings v(N-1) projects to v(N), and
  ship both." Tracked: this discipline is documented in
  `migrations/README.md` § "Adding a new migration."

**Follow-ups:**
- After 3 migrations, audit whether the migration file format is right
  (e.g. should idempotency checks be a structured list rather than
  prose? Should `applies_to` be auto-derived from the steps?).
- After the first real upgrade run on an existing AgenticApps repo,
  capture user feedback on the dry-run + confirm UX and iterate.
- Consider a future `--auto` flag for trusted environments (e.g. a
  CI step that re-runs setup against a known-clean fixture each release).

## References

- Action plan: `/Users/donald/Documents/Claude/Projects/agentic-workflow/tooling-action-plan-2026-05-02.md` (the "NEW: Migration framework" row in the in-scope table)
- Hand-off prompt Phase 4 spec: `claude-workflow-update-prompt.md` Phase 4 (Steps A–H)
- `migrations/README.md` — format specification
- `update/SKILL.md` — runtime contract
- `setup/SKILL.md` — refactored to consume migrations from baseline
- ADR-0010, ADR-0011, ADR-0012 — the gate integrations migration 0001 ships
