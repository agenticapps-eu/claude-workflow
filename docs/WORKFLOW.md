# The AgenticApps workflow (v3.0.0 — OpenSpec + Superpowers)

The short version: **planning is a spec change; execution is Superpowers; one
shell script stops you writing code before the change has been validated and
reviewed.**

This replaces the GSD phase engine as the *planning* front end. It does not
change the *execution* discipline — TDD, on-disk evidence, and independent code
review are exactly as they were. Implements core spec §16–§19 (ADR-0021); this
host's adoption is ADR-0044.

## Why

The 0.x front end moved a *phase* through CONTEXT → PLAN → execute → VERIFY, and
its durable output was a pile of phase folders. Nothing in the repo stated what
the software currently *promises* — you had to reconstruct it by reading 30
phases in order.

OpenSpec inverts that. `openspec/specs/` is the current truth, always. A change
is a *delta* against it, and finishing a change means folding the delta back in.
History becomes a by-product instead of the primary artifact.

## The four stages

```
  /opsx:explore ──▶ /opsx:propose ──▶ validate ──▶ /opsx:apply ──▶ /opsx:archive ──▶ ship
   (optional)         proposal        openspec      Superpowers     fold delta       git
                      design.md       validate      TDD, review     into specs/      commit
                      spec delta      + ≥2 AI                                        + PR
                      tasks.md        reviewers
                                          ▲
                                          └── the §18 gate blocks code until BOTH pass
```

### 1 · Propose
`/opsx:propose` (or `openspec new change <slug>`) scaffolds the change:
`proposal.md`, `design.md`, a spec delta under `specs/<capability>/spec.md`, and
`tasks.md`. Superpowers `brainstorming` feeds the design note when the change
adds UI or new architecture — the old `brainstorm-*` and `design-*` gates fold
in here.

A delta uses `## ADDED|MODIFIED|REMOVED|RENAMED Requirements` headers, and every
requirement needs at least one `#### Scenario:` block. `openspec validate` will
tell you precisely what is missing.

### 2 · Validate — **the gate**
Two independent checks, both required, both **before any code**:

| Check | What it catches | Replaces |
|---|---|---|
| `openspec validate --all` | the delta is structurally wrong or incomplete | `spec-review` |
| `run-plan-review.sh <slug>` → `REVIEWS.md` with ≥2 other-vendor reviewers | the delta describes the **wrong behavior** | `plan-review` |

Validate is a schema check. It cannot tell you the spec is wrong about the
world — that is what the reviewers are for. In the cParX pilot the Codex
reviewer returned REQUEST-CHANGES on the first real change and caught a genuine
semantic defect in the delta (a field was wrong on the fallback paths), *before
a line of code existed*. That is the whole argument for keeping this gate.

### 3 · Execute
`/opsx:apply` plus the retained Superpowers gates: TDD (RED→GREEN commit pair),
verification-before-completion (on-disk evidence, §06), and an **independent**
Stage-2 code review. Validate being green does **not** discharge the code
review — it never read your code.

Conditional gates fire on what the change touches: `/cso` on auth/storage/
secrets/LLM boundaries (always, never conditional-away), `database-sentinel` on
schema/RLS, `/qa` when a dev server is reachable, design gates on visual
surfaces, `ts-declare-first` as a CI lint.

### 4 · Archive, then ship
`openspec archive <slug> -y` folds the delta into `specs/` and moves the change
to `changes/archive/<date>-<slug>/`. **It produces no git commit.**

`archive ≠ ship`. The fold is a spec-slot operation, reviewable on its own; the
ship is a VCS operation with its own gate (`branch-close` / PR). Collapsing them
into one command is explicitly forbidden by §17 — it is how an unreviewed spec
fold rides along with a code push.

## The gate, concretely

One host-agnostic script: `~/.agenticapps/bin/openspec-change-gate.sh`. Three
modes, one rule.

| Situation | Decision |
|---|---|
| No active change | **allow** — incidental edits are not blocked |
| Edit targets `openspec/**` | **allow** — you must be able to author the change |
| Active change, `validate` fails | **block** |
| Active change, `validate` green, `REVIEWS.md` < 2 reviewers | **block** |
| Active change, `validate` green **and** ≥2 reviewers | **allow** |
| `GSD_SKIP_REVIEWS=1` | **allow** — documented, logged override |
| Unparseable stdin | **allow** — fail open on *parse* error, never on policy |

```bash
# hook mode (exit 0 allow / 2 block) — what the PreToolUse hook calls
printf '{"tool":"Edit","tool_input":{"file_path":"src/x.ts"}}' | openspec-change-gate.sh

openspec-change-gate.sh --pre-commit   # blocks a commit staging code (exit 1)
openspec-change-gate.sh --ci           # whole-repo check (exit 1)
```

Set `OPENSPEC_GATE_STRICT=1` for the stricter "no code outside a change at all"
posture. `MIN_REVIEWERS` overrides the threshold.

### Where it is wired
- **Claude** — `.claude/settings.json` `PreToolUse`, matcher
  `Edit|Write|MultiEdit|NotebookEdit`, calling a thin shim that execs the global
  script.
- **git pre-commit** — `bin/git-hooks/pre-commit`.
- **CI** — `.github/workflows/openspec-gate.yml`.

The per-agent hook is *faster feedback*. The pre-commit + CI pair is the
**guarantee**: a PreToolUse hook only sees one agent and cannot gate the session
that installed it (§18 calls this out as inherent). The git/CI floor catches any
agent — or a human.

## Agent-agnostic by construction

Three pieces, none of them Claude-specific:

1. **The `openspec` CLI** — one global binary, same verbs for every agent and
   every human. `npm i -g @fission-ai/openspec`.
2. **The spec files** — plain markdown under `openspec/`. Nothing agent-specific.
3. **The gate** — one shell script, shared by every host's hook and by CI.

Only two thin things are per-agent: the `/opsx:*` slash sugar (OpenSpec
generates it for 28 tools, including claude/codex/opencode/pi via
`--tools`) and the hook wiring. An agent OpenSpec does not support still gets
the entire workflow through the CLI plus `CLAUDE.md`/`AGENTS.md`; it just loses
the shortcut.

## What happened to the old gates

| 0.x gate | Fate | Where it lives now |
|---|---|---|
| `spec-review` | collapsed | `openspec validate --all` (stage 2) |
| `plan-review` | collapsed, **content kept** | the multi-AI review in stage 2, enforced by the §18 gate — not a standalone gate (§17 MUST NOT) |
| `code-review` | retained, always | stage 3, independent context |
| `tdd`, `verification` | retained | stage 3 |
| `security` (`/cso`) | retained, always | stage 3 |
| design gates, `qa`, `database-sentinel`, `impeccable` | conditional | stage 1/3, on their triggers |
| `ts-declare-first` | demoted | CI lint gate |
| `branch-close` | retained | stage 5 (ship) |
| GitNexus reindex | **removed** | gone (ADR-0044) |

`impeccable` and the Go skills stay behind the ADR-0021 **measured trial** — see
`MEASUREMENT.md` in `agenticapps-workflow-core`. They are not removed.

## Linear

Loose coupling, deliberately (§19). A change *may* reference a Linear issue id
in its proposal and PR body. Nothing synchronizes, nothing requires it, and no
gate checks for it. Traceability without a two-way integration to maintain.

## Migrating an existing project

`/update-agenticapps-workflow` applies migration `0032`, which installs the gate,
runs `openspec init`, collapses the gate set, and removes GitNexus.

`.planning/` is **kept**, never deleted — it is the effort history and the
backup. Converting phases into specs is a supervised, second-tier job: phases
merge into *capabilities* (not one-phase-one-spec), and a human ratifies the
result before anything is archived.
