# ADR-0037 — Phase artifacts are committed; the scaffolder never gitignores `.planning/phases/`

**Status:** Accepted
**Applies to:** `claude-workflow` (this repo); **mirrored** by `codex-workflow`
and `opencode-workflow` (vendored copy of the same standard).
**Relates to:** ADR-0036 (snapshot install), `docs/standards/gsd-binding-and-planning.md` §5.

## Context

Phase artifacts live under `.planning/phases/<NN>-<slug>/` — `CONTEXT.md`,
`PLAN.md`, `VERIFICATION.md`, `REVIEW.md`, `HANDOFF-LOG.md`, and the gate outputs.
The shared standard (`gsd-binding-and-planning.md` §5) classes them as **shared
state**: the single portable project plan that lets one host start a phase and
another host (or a later session) continue it. For that to work, they must be
**committed**.

The **dual-host workflow-testbed benchmark (rounds 1+2, 2026-07-01/02)** surfaced
recurring friction that contradicted this:

- Scaffolded testbed projects carried a whole-tree `.planning/phases/` line in
  `.gitignore`.
- **claude was the only host whose planning evidence was NOT committed** — both
  rounds. `codex` worked around it with `git add -f`; `opencode` un-ignored the
  path mid-run.
- The testbed's own notes mis-attributed the ignore to "the GSD config"
  (`workflow-testbed/benchmark/RESULTS.collected.md`), when in fact the line came
  from the benchmark harness's hand-authored `benchmark: baseline` commit.

Investigation of this repo confirmed: **claude-workflow's scaffolder emitted no
`.gitignore` at all** — neither `setup/snapshot/` nor `templates/` contained one,
and `setup/SKILL.md` never wrote one. So there was no authoritative artifact
asserting the "commit phase artifacts" policy, and nothing to stop a downstream
project, a benchmark harness, or a mistaken belief about "GSD config" from
introducing a whole-tree ignore. claude-workflow's *own* root `.gitignore`
already does the right thing (commits the tree; ignores only scratch review
files + `current-phase` + `skill-observations`), but that was never propagated to
scaffolded projects.

## Decision

Make the policy **authoritative and enforced**, on both install paths:

1. **Fresh installs** get a canonical `.gitignore`. `templates/gitignore` is the
   source of truth; `bin/build-snapshot.sh` assembles it into
   `setup/snapshot/gitignore`; `setup/SKILL.md` Step 4h lays it down — **appending
   to** any existing project `.gitignore` (never clobbering stack ignores) and
   **stripping** any whole-tree `.planning/phases/` line it finds. The baseline
   commits `.planning/phases/` and ignores only local/ephemeral paths
   (`.claude/worktrees/`, `.planning/current-phase`, `.planning/skill-observations/`,
   `*.tmp`, and narrow reviewer-scratch files *under* the tree).

2. **Existing installs** are fixed by migration `0024` (2.1.0 → 2.2.0), which
   surgically removes a whole-tree `.planning/phases/` / `.planning/` /
   `.planning/*` ignore from the project `.gitignore` if present, preserving
   every other entry (including narrow scratch ignores under the tree), then
   bumps the version.

3. **The drift guard enforces it forever.** `check-snapshot-parity.sh` §6 FAILs
   if the snapshot `.gitignore` ever ignores the phases tree — so a whole-tree
   ignore can never re-enter the seed and false-green through CI.

4. **The standard states it as a checklist line.** `gsd-binding-and-planning.md`
   conformance checklist now carries: *"MUST NOT gitignore `.planning/phases/` —
   phase artifacts are committed."*

## Consequences

- Phase evidence is committed by default on every host; no `git add -f` and no
  mid-run un-ignoring. The benchmark friction is closed at the source.
- The scaffolder now **owns a downstream `.gitignore` contribution** it did not
  before. It is additive/merge-only (like the CLAUDE.md reference-block append),
  so it does not overwrite a project's language/stack ignores.
- Narrow, intentional ignores of specific scratch files *under* the phases tree
  (e.g. `.planning/phases/*/.codex-review.md`) remain allowed — only a
  **whole-tree** ignore is prohibited. The guard patterns and the migration sed
  are anchored to a bare-directory line, so they spare those.
- **Downstream mirror obligation:** `codex-workflow` and `opencode-workflow` ship
  a vendored copy of `gsd-binding-and-planning.md` and their own scaffolders.
  They MUST mirror this: scaffolded `.gitignore` must not ignore
  `.planning/phases/`, and their update path must strip a whole-tree ignore from
  existing installs. Tracked here and in migration `0024`'s "Downstream hosts"
  section.

## Alternatives considered

- **Documentation only (no shipped `.gitignore`).** Rejected: leaves nothing
  authoritative on the install path — the exact gap that let the benchmark
  baseline and the "GSD config" belief invent the ignore. The task explicitly
  wants fresh installs to receive the corrected file.
- **Own/overwrite the whole project `.gitignore`.** Rejected: clobbers stack
  ignores. The merge-and-strip approach preserves the project's own entries.
- **Fix only the benchmark harness.** Rejected: treats the symptom. The harness
  bug is real, but the workflow still needs a positive, enforced policy so the
  next scaffolded project (benchmark or not) commits its plan.

## References

- Migration: `migrations/0024-commit-planning-phases.md`
- Standard: `docs/standards/gsd-binding-and-planning.md` §5 + conformance checklist
- Snapshot source / laydown: `templates/gitignore`, `bin/build-snapshot.sh`, `setup/SKILL.md` Step 4h
- Drift invariant: `migrations/check-snapshot-parity.sh` §6
- Evidence: `workflow-testbed/benchmark/RESULTS.collected.md`, rounds 1+2 (2026-07-01/02)
