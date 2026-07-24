# ADR-0044: Adopt the OpenSpec + Superpowers front end (spec 1.0.0)

**Status**: Accepted  **Date**: 2026-07-24  **Linear**: —

Supersedes ADR-0003 (GSD entry points), ADR-0007 (bind-upstream GSD),
ADR-0018 (multi-AI plan-review gate — **retargeted, not reversed**),
ADR-0020 + ADR-0039 (GitNexus), ADR-0025 (review-gate phase resolution).
Marks `docs/standards/gsd-binding-and-planning.md` SUPERSEDED.
Implements core spec §16–§19 (core ADR-0021).

## Context

The 0.x front end was the GSD phase engine. A phase moved
CONTEXT → PLAN → execute → VERIFY → REVIEW, and its durable output was a pile of
phase folders under `.planning/phases/`. Two problems compounded over 31
migrations:

1. **Nothing in the repo stated what the software currently promises.** Truth
   had to be reconstructed by reading phases in chronological order and
   mentally applying each one. `.planning/` is an excellent *effort* record and
   a poor *state* record.
2. **The gate set kept growing.** §02 listed eleven gates by 0.9.0, several
   with overlapping jobs (`spec-review` and `plan-review` both reviewed
   pre-execution artifacts) and each with its own trigger, evidence file, and
   failure mode. More surface than the discipline it protected.

The 2026-07-24 cParX pilot ran the alternative end to end — propose → validate
→ multi-AI review → TDD → archive → ship in ~30 minutes in a throwaway worktree
— and it passed. The finding that settled it: the Codex reviewer returned
REQUEST-CHANGES on the **first real change** and caught a genuine semantic
defect *in the spec delta* (a field was wrong on the fallback paths, where a
rule rather than a model produces the value). It was fixed before any code
existed. That is the ADR-0018 value proposition, arriving earlier and cheaper
than ADR-0018 could deliver it.

## Decision

Adopt **OpenSpec as the planning front end**, keep **Superpowers as the
execution discipline**, and make the four-stage lifecycle
(propose → validate → execute → archive, then ship) the unit of product work.

Five decisions, each with a live alternative that was rejected:

### 1. Bind OpenSpec upstream; do not re-port it

The `openspec` CLI is a standalone, agent-agnostic binary. This repo installs it
and calls it. `openspec init --tools claude --profile core` generates the spec
slot and the `/opsx:*` command files; none of it is vendored.

*Rejected:* re-porting the workflow into our own commands, the way GSD was
bound per host. It would put us back in the business of tracking someone else's
semantics across four host repos — the exact cost ADR-0007 was written to avoid,
and OpenSpec already supports all four hosts natively via `--tools`.

### 2. Collapse `spec-review` and `plan-review` into stage 2 — but KEEP the multi-AI review

`openspec validate --all` discharges `spec-review`'s structural role, and does
it *before* implementation rather than after.

The multi-AI review is **kept and retargeted**: reviewers now critique the
active change (proposal + design note + spec delta) instead of a `PLAN.md`,
evidence is `changes/<slug>/REVIEWS.md`, the ≥2-reviewer rule and both escape
hatches are unchanged. Per §17 it is not a standalone gate — its obligation is
discharged inside stage 2 and enforced by the §18 change-gate.

*Rejected:* dropping it and letting `validate` stand alone. Validate is a schema
check; it cannot tell you the delta describes the wrong behavior. Dropping it
would re-open ADR-0018, whose failure mode (cparx phases 04.9→05 silently
skipping review for 8 phases) is documented and recent. The pilot then produced
the counter-evidence in one change.

### 3. One host-agnostic gate script, with a git/CI floor underneath

The enforcement surface is a single shell script
(`~/.agenticapps/bin/openspec-change-gate.sh`) implementing §18's exit-code
truth table. Every surface calls it: the Claude `PreToolUse` hook (via a thin
project-local shim), the git `pre-commit` hook, and CI.

The **floor is the guarantee**; the per-agent hook is fast feedback. A
`PreToolUse` hook is loaded at session start, so it cannot gate the session that
installed it (§18 names this inherent, not a defect), and it only ever sees one
agent. The git/CI pair catches every agent and a human editor.

*Rejected:* per-host gate implementations. Four implementations of one rule is
four places for it to drift, and none of them is testable with a simulated
payload the way one script is.

### 4. Remove GitNexus entirely

The reindex hook, its scripts, its MCP wiring, and the `.gitnexus/` data dir
(including a 57MB binary) leave the workflow.

It cost more than it returned: it rewrote `AGENTS.md`/`CLAUDE.md` as a side
effect of indexing, which produced migrations 0026, 0029, 0030, 0031 and 0043 —
five migrations and a three-layer data-loss guard, all defending a project
instruction file against our own tooling.

*Retained deliberately:* every one of those migrations, their fixtures, and
ADRs 0020/0039/0041/0043. §08 is supersede-don't-delete, and they are the replay
path for any project upgrading from a pre-3.0.0 version. Their **tests** are
retired to assert the payload's absence, so a revert that reintroduces the
engine fails the suite. `setup/SKILL.md` also keeps the §11 anchor alternation:
a consumer installed before 3.0.0 may still carry a region, and that branch is
the only thing standing between its §11 block and the next `analyze`.

### 5. `archive ≠ ship`

`openspec archive` folds the delta into `specs/` and moves the change directory.
It produces no git commit. Shipping is a separate act with its own gate.

*Rejected:* one command that folds and pushes. The fold is a spec-slot operation
worth reviewing on its own; collapsing them is how an unreviewed spec fold rides
along with a code push.

## Consequences

**Good.** `openspec/specs/` states current truth, so "what does this promise?"
is a read, not a reconstruction. The adversarial review moved to the cheapest
point in the cycle — before code. Enforcement is one testable script instead of
per-host logic, and it now covers humans and non-Claude agents via the git/CI
floor. The gate set shrank: two gates collapsed, one demoted to lint, six made
conditional.

**Costs, stated plainly.**

- The workflow now depends on the `openspec` CLI. Without it the gate blocks
  under an active change (an unvalidatable change must not pass) — deliberate,
  but it is a hard dependency where there was none.
- Stage 2 needs **≥2 other-vendor reviewer CLIs**. A machine with only Claude
  installed cannot clear the gate without the logged `GSD_SKIP_REVIEWS=1`
  override.
- `.planning/` is now dead weight in the repo until someone folds it into
  capabilities. Migration 0032 deliberately does not attempt that: phases merge
  into capabilities many-to-one, and a wrong merge writes a false promise into
  the spec slot. It is a supervised job needing human ratification.
- `impeccable` and the Go skills stay behind the ADR-0021 measured trial. This
  ADR does not remove them and does not pre-judge that trial.
- Five migrations' worth of test coverage was retired rather than migrated.
  The behavior they covered no longer exists; keeping stubbed versions would
  have tested the stubs.

## Alternatives Rejected

- **Keep GSD, add a spec slot beside it.** Two planning surfaces, and the
  question "which one is authoritative?" answered differently by each agent.
- **Adopt the OPSX Expanded profile.** Its `/opsx:verify` overlaps
  `superpowers:verification-before-completion`. Two verification surfaces is how
  one of them gets skipped; Superpowers stays the authority.
- **Tight Linear coupling.** §19's loose convention (a change *may* reference an
  issue id; nothing synchronizes) buys traceability without a two-way
  integration to maintain. A sync would be a fourth thing that can drift.
- **`OPENSPEC_GATE_STRICT=1` as the default** ("no code without a change").
  Judged too aggressive: it blocks typo fixes and config tweaks. It ships as an
  opt-in env var.
