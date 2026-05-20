# ts-declare-first

Operator guide for the declare-first TypeScript skill. Implements
`agenticapps-workflow-core` spec §13.

## What this skill does

Guides authoring a new TypeScript module via three atomic commits:

| Phase | File written              | Commit prefix              | Verification          |
|-------|---------------------------|----------------------------|-----------------------|
| 1     | `<name>.declare.ts`       | `declare(ts): <name> ...`  | `tsc --noEmit`        |
| 2     | `<name>.test.ts`          | `test(ts): <name> ... RED` | test runner reports expected failure |
| 3     | `<name>.ts`               | `feat(ts): <name> ... GREEN` | test runner reports pass |

The three-commit shape is structural evidence the discipline was
followed (spec §13 verification gate).

## When to use it

- **You're authoring a new TS module's public API surface** (a
  library function, a class, an exported type, a service interface).
  The discipline pins the contract before any implementation exists.
- **You want to strengthen TDD for type-heavy code.** In ordinary
  TDD, signatures emerge from tests. Here, signatures are fixed
  first; tests exercise signature + behaviour; implementation has
  no room to diverge.
- **The phase plan introduces a new TS module in a TS-primary
  project.** Per §13's implicit trigger, this is the default when
  `package.json` declares TypeScript as the primary language.

## When NOT to use it

- **Refactoring within an existing module** where the public API
  doesn't change. The discipline targets new API surface, not
  internal restructure.
- **Bug fixes that don't change signatures.** Use ordinary TDD.
- **One-off scripts** with no public API.
- **Non-TypeScript code.** This skill is TypeScript-specific by
  design; the discipline doesn't translate cleanly to dynamically-
  typed languages.

## How to invoke

Explicit:

> "I'm starting a new TS module `lib/<name>/`. Walk me through the
> ts-declare-first discipline."

The skill loads, the model follows the three-phase procedure in
`SKILL.md`, producing one commit per phase. The model refuses to
bundle commits.

Implicit (future): when the host's GSD design phase wires §13's
implicit trigger, new TS modules in TS-primary projects auto-invoke
this skill.

## Resolution mechanism (Phase 2)

Phase 2's tests need to import the declared surface even though the
implementation file doesn't exist yet. Pick one of:

| Mechanism                    | Best for                                                       |
|------------------------------|----------------------------------------------------------------|
| **Path alias** in tsconfig   | Larger projects where one tsconfig change is amortised.        |
| **Stub `<name>.ts`** at Phase 1 | Smaller projects where the stub-then-replace cycle is local. |
| **Direct `.declare` import** | One-off modules; trades contract-test purity for setup speed.  |

Per §13 the host picks. This skill defers to the operator.

## Refusals

The skill refuses to proceed when:

- Phase 1 and Phase 3 are combined in one commit.
- The declare file contains implementation bodies.
- Phase-2 tests pass on first run (no RED observed).

Each refusal cites the specific §13 / §06 contract being violated
and instructs the operator on how to recover.

## Templates

Starter files (`./templates/`):

- `example.declare.ts` — bounded-queue Phase-1 shape.
- `example.test.ts` — bounded-queue Phase-2 shape.
- `example.impl.ts` — bounded-queue Phase-3 shape.

Copy and adapt. The bounded-queue example is non-normative — it
mirrors spec §13's illustrative example so reviewers can see the
contract shape in a familiar form.

## Spec references

- §13 — declarative contract this skill satisfies.
- §06 — Evidence Rules (Phase-2 expected-failure output, Phase-3
  pass output).
- §02 — Hook Taxonomy (`tdd` gate this strengthens).
