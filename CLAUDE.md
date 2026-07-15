<!--
  This block MUST stay ABOVE the `<!-- gitnexus:start -->` region below.
  `gitnexus setup` regenerates everything between its start/end markers, so a
  §11 block placed inside them (e.g. before the first `## ` heading, which is
  where migration 0014 injects it into scaffolded projects) would be silently
  dropped on the next run. Above the region is also the earliest point in the
  file, which is what spec §11's placement SHOULD asks for.

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

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **claude-workflow** (2306 symbols, 2439 relationships, 2 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/claude-workflow/context` | Codebase overview, check index freshness |
| `gitnexus://repo/claude-workflow/clusters` | All functional areas |
| `gitnexus://repo/claude-workflow/processes` | All execution flows |
| `gitnexus://repo/claude-workflow/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
