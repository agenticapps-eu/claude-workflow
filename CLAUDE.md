<!--
  This block sits at the top of the file, which is what spec §11's placement
  SHOULD asks for.

  There is no `<!-- gitnexus:start -->` region below it: the GitNexus section
  was removed from this repo's instruction files (v2.9.0) and GitNexus itself
  was removed from the workflow entirely in v3.0.0 (ADR-0044). Migration 0029's
  anchor rule still exists and still matters — a consumer repo installed before
  3.0.0 may still carry a region, and §11 must stay anchored above it or that
  project's next `analyze` silently eats the block. Do not read this file's
  lack of a region as evidence the rule is obsolete.

  Verbatim from the spec — do not edit. Substitution is permitted only inside
  `{{...}}`; altering any surrounding prose, the rule numbers, or the
  anti-pattern bullets is non-conformant (spec §11 Conformance). Guarded by
  `test_claude_md_reproduces_spec_11_verbatim` in migrations/run-tests.sh,
  which diffs it against templates/spec-mirrors/.
-->
<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->
## Coding Discipline (NON-NEGOTIABLE)

These four rules are reread every session because the failure modes
they prevent recur every session.

### 1. Think Before Coding

State assumptions explicitly before writing any line. When the request
is ambiguous, present the alternative interpretations and ask which
applies. When the request contradicts itself, surface the contradiction
rather than silently picking one side. When you are confused, stop and
ask — confusion is signal, not friction.

Anti-patterns this rule prevents:

- Diving into implementation without restating what was actually requested.
- Picking one reading of an ambiguous instruction silently and shipping it.
- Treating two contradictory requirements as if both can be satisfied without comment.
- Treating "I'll figure it out as I go" as a substitute for understanding the goal.
- Generating code first and asking clarifying questions only after a failure.

### 2. Simplicity First

Write the smallest thing that satisfies the request. No features
beyond what was asked. No abstractions for code with one caller. No
flexibility for callers that do not exist. No error handling for
scenarios that cannot occur given the code's invariants. The
senior-engineer test: would a senior engineer reviewing this say it is
overcomplicated for what was asked?

Anti-patterns this rule prevents:

- Adding a helper function "in case we need to call this from elsewhere later."
- Introducing a configuration option for behavior that has one consumer.
- Wrapping internal calls in try/catch when no internal caller throws.
- Designing for a hypothetical second consumer that does not exist.
- Replacing three similar lines with a parameterised abstraction.
- Shipping a "framework" when a function would do.

### 3. Surgical Changes

Touch only what you must to satisfy the task. Adjacent code is out of
scope. Match the existing style of the file you are editing rather than
the style you would have chosen. Clean up only the orphans your own
change created. If you notice an unrelated improvement, leave it as a
follow-up note, not a diff.

Anti-patterns this rule prevents:

- Reformatting untouched lines to "fix style" while editing nearby.
- Refactoring a function that the task did not name.
- Renaming a variable across the file because the new name is "better."
- Deleting code you decided is unused without verifying it has no callers.
- Pulling adjacent code into the diff because "while I'm here."
- Bundling a cleanup pass into a feature commit.

### 4. Goal-Driven Execution

Every task is a goal, not a list of imperative steps. Restate the goal
in a form that is verifiable from on-disk artifacts before writing any
code. For bug fixes: write the failing test that reproduces the bug
first, then make it pass. For performance work: capture the measurement
first, then change the code, then capture it again. For behavioral
changes: define the assertion the diff must satisfy before the diff
exists. "Done" is "the goal is verifiably satisfied," not "the code now
exists."

Anti-patterns this rule prevents:

- "Fix the bug" without a failing test that reproduces it.
- "Improve performance" without a measurement before and a measurement after.
- "Make it work" without a definition of "work" the diff can be checked against.
- Marking a task complete on the basis of "the code now exists" rather than "the goal is satisfied."
- Writing implementation before there is anything that can fail to confirm the goal is met.

These four rules apply to every code-touching turn. They do not
replace the commitment ritual, the rationalisation table, the red
flags, or the evidence rules — they sit alongside them as the
session-level discipline the model brings to every diff.

## Development Workflow

Planning is an **OpenSpec change**, not a GSD phase. Every unit of product work
moves through four stages (core spec §17):

**propose** → **validate** → **execute** → **archive**, then **ship** as a
separate act.

- `openspec/specs/` is durable current truth · `openspec/changes/` are in-flight
  deltas · `changes/archive/` is history.
- **Before any code**, the active change MUST have `openspec validate --all`
  green **and** `REVIEWS.md` carrying ≥2 independent other-vendor reviewers.
  Both clauses are enforced by the §18 change-gate at `PreToolUse`, at
  `git commit`, and in CI. Blocked edits mean the gate is working.
- `archive ≠ ship` — `openspec archive` folds the delta into `specs/` and
  produces **no** git commit.
- Execution discipline is unchanged Superpowers: TDD, on-disk evidence, and an
  independent Stage-2 code review that `validate` does not discharge.

The OpenSpec CLI is bound **upstream** — run `openspec --help` and use the verbs
it reports; the installed CLI is authoritative over any prose here.

**Full explainer: [`docs/WORKFLOW.md`](docs/WORKFLOW.md).** Gate-by-gate
enforcement contract: [`docs/ENFORCEMENT-PLAN.md`](docs/ENFORCEMENT-PLAN.md).

## Session handoff

Before ending any session — when asked to exit, when the final task is done, or
when context is getting full — write `session-handoff.md` in the project root.
It survives `/clear` and `--resume`, so it is the primary continuity mechanism
across sessions. Keep it under 150 lines.
