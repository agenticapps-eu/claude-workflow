# ADR-0045: Re-vendor the runtime instruction payload, and reconcile §04

**Status**: Accepted  **Date**: 2026-07-28  **Linear**: —

Closes the §04 divergence disclosed in [ADR-0040](0040-spec-0.9.0-conformance.md)
and completes the front-end swap of [ADR-0044](0044-openspec-superpowers-adoption.md).
Implemented by migration `0033` (3.0.0 → 3.1.0).

## Context

ADR-0044 retired GSD and migration `0032` retargeted the *trigger skill*
(`skill/SKILL.md` → `.claude/skills/agentic-apps-workflow/SKILL.md`) onto the
OpenSpec lifecycle. Two vendored documents were not retargeted with it:

- `templates/.claude/claude-md/workflow.md` — 12 GSD references, 0 OpenSpec.
- `templates/workflow-config.md` (and its snapshot mirror) — 4 and 0.

`workflow.md` is the file every scaffolded `CLAUDE.md` links to. **It is what
an agent reads at runtime.** So a project could apply `0032`, pass all fifteen
of its post-checks, report `version: 3.0.0` / `implements_spec: 1.0.0`, and
still be told — in the document its instruction file points at — that planned
work goes through `/gsd-execute-phase`, that it should "Check GSD state", that
the gates live in `.planning/config.json` → `hooks` (a tree `0032` Step 5
deleted), and, in a section titled `## GSD Workflow Enforcement`, that it must
"not make direct repo edits outside a GSD workflow".

That is not stale prose. It is the instruction surface contradicting the
enforcement surface: the §18 change-gate blocks the edits that document tells
the agent to make, and the agent has no way to tell which of the two is current.

Eleven repos carry a vendored copy; seven are at `version: 3.0.0` /
`implements_spec: 1.0.0` and can apply the fix. Five of those seven were still
serving the GSD-teaching bytes at the time this shipped. Per-repo state is in
`0033`'s `## Downstream` table.

Two facts about how this survived five migrations matter more than the defect:

1. **It was noticed and not fixed.** `skill/SKILL.md`'s `## Spec deltas`
   section, since 0.9.0, disclosed the §04 half of the divergence in a bullet
   ending "needs its own migration; tracked separately". The disclosure was
   honest and the tracking was a sentence in a file nobody re-reads.
2. **Nothing asserted it.** `check-snapshot-parity.sh` checks JSON shape, hook
   bindings, version stamps and the §11 mirror. `run-tests.sh` checks migration
   idempotency. No check ever read what the shipped documents *say*.

## Decision

**1. Re-vendor both documents onto the OpenSpec lifecycle**, and ship migration
`0033` (3.0.0 → 3.1.0) to carry them to existing installs by the same byte-copy
idiom `0031` Step 1 and `0032` Step 6 use.

The `## GSD Workflow Enforcement` section is **deleted outright**, not
retargeted. Its job — "route work through a planning command before editing" —
is now done by `/opsx:propose` and enforced programmatically by the §18 gate.
Prose asking the agent to self-police an entry point it can no longer name is
strictly worse than the gate that blocks the edit.

**2. `workflow-config.md` is re-vendored by SECTION, not byte-copy.** Setup
substitutes `{{PROJECT_NAME}}`, `{{REPO}}`, `{{CLIENT}}`, `{{BUDGET}}` and the
tech-stack placeholders with the project's real values, and `setup/SKILL.md`'s
own post-check asserts no `{{...}}` survives. A byte-copy would restore every
placeholder and destroy the project's configuration. `0033` Step 2 replaces
exactly `## Superpowers Integration Hooks` and splices — resuming at the next
`## ` heading — so a project-owned section below it survives verbatim.

**3. §04 is reconciled by construction.** The vendored `workflow.md` now
carries the canonical red-flag block byte-for-byte — the same heading and the
same fourteen flags as `skill/SKILL.md`, replacing a reworded 13-flag variant
whose flags 1, 6, 12 and 13 differed. The `## Spec deltas` bullet that disclosed
the divergence is **deleted**, because the divergence is gone. That is a
reduction in declared deltas, not a change of claim: `implements_spec` stays
`1.0.0`.

**4. `.claude/claude-md/workflow.md` is NOT deleted.** One consuming repo
(`agenticapps-dashboard`) has already removed it, and that is a defensible end
state — the trigger skill says everything this file says. But
`.claude/hooks/normalize-claude-md.sh` keys off the file's *existence* to
collapse a `<!-- GSD:workflow -->` marker block, and two repos still carry those
markers. Removing the file changes that hook's behaviour. If it should go away,
that is its own migration with the hook change alongside it.

**5. The gap gets a regression guard, because a disclosure is not one.**
`migrations/run-tests.sh` gains two tests:

- `test_no_gsd_refs_in_shipped_templates` — fails on `/gsd-`, `GSD state` or
  `gsd-execute-phase` anywhere under `templates/` or `setup/snapshot/`, with an
  explicit, reasoned exclusion list (see below).
- `test_workflow_md_red_flags_match_canonical` — extracts the §04 block from
  `skill/SKILL.md`, the template and the snapshot, and fails on any byte of
  difference. Reconciling the two copies without pinning them is how they drift
  apart again.

## Alternatives Rejected

- **Byte-copy `workflow-config.md` like the other two.** Simplest, symmetric,
  and it silently destroys every consuming project's name, repo, client, budget
  and stack. Rejected on inspection of `setup/SKILL.md` Step 4b.
- **Delete `.claude/claude-md/workflow.md` and let the trigger skill be the
  only instruction surface.** The right end state and the wrong migration:
  `normalize-claude-md.sh` behaviour is coupled to the file's existence, and
  changing a hook is not a re-vendor. Deferred, not dismissed.
- **`sed` the GSD strings out instead of re-vendoring.** "Contains no `/gsd-`"
  is a weaker invariant than "byte-identical to the vendored source", and a
  string-level patch would leave the document's *structure* — pre-phase /
  per-plan / post-phase, wave execution, phase verification — describing an
  engine that no longer exists.
- **Scope the regression guard to the two fixed files.** It would pass today
  and say nothing about the next document that goes stale. The value of the
  check is precisely that it covers files nobody is currently thinking about.
- **Make the guard exclusion-free by fixing every hit.** Two of the remaining
  hits are shipped hooks whose stderr advice names a GSD command
  (`database-sentinel.sh` → `/gsd-discuss-phase`,
  `normalize-claude-md.sh` → `/gsd-profile-user`); rewriting either changes
  generated content or advice about a `.planning/current-phase/` sentinel path
  that `0032` deliberately left alone, and both carry fixture churn. One is
  `templates/claude-md-sections.md`, deprecated and retained *because* migration
  `0009` greps those exact strings to detect a legacy inlined paste — rewording
  it breaks detection for the repos that still need it. One is
  `templates/gsd-patches/`, a mirror of an external tool's config directory that
  setup never installs. Each is excluded by path with its reason recorded in the
  test; the list is meant to shrink.

## Consequences

- **Every scaffolded project's runtime instruction surface now matches its
  enforcement surface.** The document CLAUDE.md links to describes the lifecycle
  the §18 gate actually enforces.
- **A hand-edited local copy is not clobbered.** All three steps are
  vendored-file replacements, so the update runtime presents the 3-way
  Replace / Keep / Vendor-local pick defined in `update/SKILL.md`, defaulting to
  Keep. An operator who chooses Keep stays on GSD-teaching prose *by explicit
  decision* — which is the point of the prompt.
- **But every eligible copy turned out to be divergent**, so the prompt fires on
  all of them and the safe default is the wrong answer for six of the seven. The
  divergence is *age*, not customization — copies vendored before `0027`
  repointed `ENFORCEMENT-PLAN.md` and before the `observability-postphase-scan.sh`
  hook was dropped at 2.5.0. Rollout guidance and the per-repo table live in
  `0033`'s `## Downstream`. The general lesson: "default to Keep" is right when
  divergence means customization and wrong when it means staleness, and the
  prompt cannot tell them apart. Whoever runs the migration must.
- **No repo carries the `## GSD Workflow Enforcement` section inlined in
  `CLAUDE.md`.** An earlier revision of this ADR said `agents-task-viewer` did;
  that was a stale measurement inherited from the defect report, and it was
  already untrue when `0033` shipped. `0033` still touches no `CLAUDE.md` — the
  reason is unchanged (`0029`/`0030`/`0043`), and `cparx` does still carry an
  older *inlined* workflow block that needs a hand edit.
- **Three follow-ups are now named rather than latent:** the two hooks' stale
  advice; `docs/ENFORCEMENT-PLAN.md`, which the vendored `workflow.md` cites as
  its enforcement contract and which is still written in phases, `*-PLAN.md` and
  `/gsd-review`; and the open question below.

## Open question this raised — should `workflow.md` exist at all?

`agents-task-viewer` answered it locally before this migration did: it replaced
its vendored copy with a **67-line companion** that states the three disciplines
and then points at `.claude/skills/agentic-apps-workflow/SKILL.md` as
authoritative, under an explicit rule that it *"never duplicates the SKILL's
lifecycle or gate rules (§11: one source, no drift)"*.

That is a better structure than what this ADR ships, and it is worth saying so
plainly. What `0033` vendors is ~190 lines that restate the trigger skill's
commitment ritual, lifecycle table, gate map, rationalization table and red
flags. Two copies of one rule set is the exact failure this migration exists to
repair — and the `test_workflow_md_red_flags_match_canonical` guard added here
is a *pin holding two copies in sync*, which is a workaround for having two
copies at all.

Not resolved here, because collapsing the file is a different change with real
coupling: `CLAUDE.md`'s `## Workflow` link, `0000`/`0009`'s post-checks that
grep its headings, and `normalize-claude-md.sh`'s dependence on its existence
(live in two repos today). Tracked as the successor to this ADR.
