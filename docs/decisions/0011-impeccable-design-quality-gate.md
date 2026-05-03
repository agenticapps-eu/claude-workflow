# ADR-0011: impeccable as design-quality gate (pre-phase critique + finishing audit)

**Status:** Accepted
**Date:** 2026-05-03
**Linear:** —
**Phase:** Phase 2 of `feat/wire-go-impeccable-database-sentinel`

## Context

`gstack:/design-shotgun` generates 3–4 UI variants per phase but offers no
quality filter — every variant reaches the user, including ones that exhibit
the standard AI-slop tells (purple gradients, Inter-everywhere, weak
hierarchy, generic empty states). Picking from a slate that includes obvious
slop wastes user attention and pulls the chosen design toward the median.

`pbakaus/impeccable` is a Claude Code skill (also Cursor / Gemini / Codex)
that ships:

- 23 commands (`/polish`, `/audit`, `/critique`, `/typeset`, plus 19 more)
- 7 reference files (typography, OKLCH color, spatial design, motion,
  interaction, responsive, UX writing)
- An anti-pattern detector for ~24 AI-slop tells
- Active growth (~1.6k stars, ~640/day)

The skill composes naturally with the existing two-stage pipeline:
`/design-shotgun` produces variants → `impeccable:critique` scores each →
sub-bar variants are eliminated → user picks from the surviving slate.
Finishing-stage `impeccable:audit` then runs against the deployed component
before branch close.

## Decision

Wire `impeccable` into the AgenticApps workflow at two gate points:

1. **Pre-phase (`design_critique`)** — fires after `/design-shotgun` and
   before the user picks. Runs `impeccable:critique` against each variant,
   records scores in UI-SPEC.md, eliminates sub-bar variants. Quality bar
   is a numeric threshold from the critique output (default ≥ 90 — a
   project's `workflow-config.md` can override).
2. **Finishing (`impeccable_audit`)** — fires when a frontend-touching
   feature branch is ready to merge. Runs `impeccable:audit` against the
   deployed component. Blocks branch close if Red findings remain unresolved.

Patches landed (per action plan §1):

- `templates/workflow-config.md` — Pre-Phase hook table row
- `templates/config-hooks.json` — `pre_phase.design_critique` and
  `finishing.impeccable_audit` entries
- `templates/claude-md-sections.md` — Pre-Phase Hook 1 expanded
- `docs/ENFORCEMENT-PLAN.md` — Phase planning gates row

## Alternatives Rejected

- **Run impeccable as a Stage 2 reviewer subagent instead of a pre-phase
  gate.** Rejected — by Stage 2 the design is already chosen and partially
  implemented. Catching slop after the user has anchored on a variant means
  either rework or accepting the slop. Pre-phase critique catches it before
  anchor.
- **Run impeccable only at finishing, not pre-phase.** Rejected — same
  anchor problem. Finishing audit alone catches polish issues but not
  fundamental design choice issues (e.g. picking a brutalist layout for a
  consumer payment flow). Pre-phase + finishing gives two distinct catches.
- **Trust /design-shotgun's variant generation to avoid slop without an
  external check.** Rejected — `/design-shotgun` is a divergent generator,
  not a quality filter. Asking it to self-filter creates a feedback loop
  bias toward whatever its model considers "safe." Independent critic.
- **Build our own anti-slop detector instead of adopting impeccable.**
  Rejected — duplicating 24 anti-pattern rules + 7 reference docs is months
  of work. Adopt + steal the methodology if needed for our own meta-skills.

## Consequences

**Positive:**
- Variant slates surface higher-quality designs by default; user attention
  is preserved.
- Finishing audit catches polish drift between mockup and implementation.
- Composes cleanly with existing two-stage review (orthogonal — impeccable
  audits design, two-stage review audits code).
- Anti-slop bar improves consistency of client-facing visual identity.

**Negative:**
- Adds one external skill dependency. Bus factor: solo maintainer
  (`pbakaus`); MIT-licensed; can fork if abandoned.
- Pre-phase critique adds ~30 seconds per UI phase. Justified by the cost
  of redoing a design picked from a sub-par slate.
- Quality bar threshold needs project-by-project calibration (default ≥ 90
  may be too strict for prototype phases).

**Follow-ups:**
- After 4 weeks of usage, review which projects override the quality bar
  and at what value. If the default is consistently overridden in one
  direction, adjust.
- Consider a `--prototype` flag that lowers the bar for non-production work.

## References

- Action plan: `/Users/donald/Documents/Claude/Projects/agentic-workflow/tooling-action-plan-2026-05-02.md` §1
- `pbakaus/impeccable` skill: installed at `~/.claude/skills/impeccable/SKILL.md`
- Composes with: `gstack:/design-shotgun`, `superpowers:requesting-code-review`
