# ADR-0016: Mattpocock `improve-codebase-architecture` audit + scheduling

**Status:** Accepted
**Date:** 2026-05-03
**Linear:** —
**Phase:** Phase 3 of `feat/programmatic-hooks-architecture-audit`

## Context

The AgenticApps enforcement-first workflow optimizes per-PR quality but
has no scheduled mechanism to catch **cross-PR architectural drift** —
the "we shipped 12 clean PRs and the directory is now a swamp" problem.
Synthesis report §1 calls this out as the gap mattpocock's
`improve-codebase-architecture` closes.

The skill ships:

- A repeatable, non-vague vocabulary (`module`, `seam`, `depth`, `leverage`,
  `locality`, `deletion test`) for naming refactor candidates
- A reading order: `CONTEXT.md` (domain glossary) → `docs/adr/` (decisions
  not to re-litigate) → codebase walk via `subagent_type=Explore`
- A nomination format: numbered candidates as Files / Problem / Solution /
  Benefits, framed in locality and leverage
- The **deletion test**: if deleting a module concentrates complexity,
  it earns its keep; if it just moves complexity, it's a pass-through

The companion `grill-with-docs` skill produces `CONTEXT.md` interactively
and is a soft prerequisite — without `CONTEXT.md`, the audit lacks domain
language to anchor recommendations.

## Decision

Install both skills globally:

- `~/.claude/skills/mattpocock-improve-architecture/SKILL.md` (5.1KB)
- `~/.claude/skills/mattpocock-grill-with-docs/SKILL.md` (3.6KB)

Cloned from `mattpocock/skills` upstream; copied verbatim (no fork) so
upstream improvements flow naturally with `git pull`.

**Wire as non-mandatory.** Donald invokes `/improve-codebase-architecture`
manually per project at ~weekly cadence. Phase 4 of this work ships the
SessionStart reminder skill + LaunchAgent cron that nags when audits go
stale; Phase 4 is the **scheduling** layer, this ADR is the **install**
layer.

**Refactor candidates land in Linear, never auto-applied.** The skill
nominates; the user triages; accepted candidates become normal Linear
issues that flow through the standard discuss → plan → execute pipeline.
This preserves the verification-before-completion gate: agentic refactor
proposals can be confidently wrong, so they go through the same review
discipline as any other code change.

### Q3 — cparx specific

User chose Q3 option C: "Install + CONTEXT.md + run first audit, file
findings in Linear backlog." The install part (this ADR) is complete; the
interactive parts (`/grill-with-docs` against cparx, then
`/improve-codebase-architecture` against cparx) require a user-driven
session and are documented as deferred follow-ups in P3 VERIFICATION.md
+ session-handoff.md.

## Alternatives Rejected

- **Adopt only `improve-codebase-architecture`, skip `grill-with-docs`.**
  Rejected — the audit skill's quality depends on a domain-language
  anchor; without `CONTEXT.md`, recommendations drift into generic
  "consider extracting a service" output. Pairing them is the spec
  recommendation.
- **Fork the skills to AgenticApps voice immediately.** Rejected —
  premature. Upstream may iterate on the prompts; forking now means
  carrying merge churn forever. Adopt verbatim, observe usage for 4-8
  weeks, fork only if voice friction proves real (e.g. mattpocock's
  rejection of "boundary" creates collisions with our existing CSO
  vocabulary).
- **Run the audit on every PR (CI gate) instead of weekly.** Rejected —
  too noisy; per-PR audits would surface short-lived drift the next PR
  resolves. Weekly cadence on stable code is the right granularity for
  cross-PR drift catching.
- **Build our own architecture-audit skill in AgenticApps voice.**
  Rejected — months of work to reproduce the deletion test + locality/
  leverage vocabulary. Mattpocock's framing is already battle-tested
  (Pragmatic Programmer / DDD / Ousterhout heritage). Steal the work.

## Consequences

**Positive:**
- Cross-PR architectural drift gets a named, measurable, repeatable gate.
- The `LANGUAGE.md` vocabulary is portable to other AgenticApps review
  skills (CSO, code-reviewer) — could harmonize over time.
- `CONTEXT.md` becomes a reusable artifact for any future skill that
  needs a domain glossary.

**Negative:**
- Adds two external skills with bus-factor risk (mattpocock is a solo
  maintainer of a popular but personal repo). Mitigation: skills are
  markdown SKILL.md; we can fork the snapshot we have if upstream
  abandons.
- The deletion test plus locality/leverage vocabulary is opinionated.
  Some refactor proposals will be confidently wrong — we mitigate via
  the "Linear backlog only, never auto-apply" rule.
- Vocabulary collision risk: mattpocock rejects "boundary" and
  "service"; our existing prose uses both. If the skill's recommendations
  argue with the project's documented decisions (e.g. an ADR that
  references "boundary"), the user may need to harmonize manually.

**Follow-ups:**
- After 4 weeks of usage, evaluate if `mattpocock-diagnose`,
  `mattpocock-to-prd`, or `mattpocock-to-issues` would compound. Linear
  backlog issues filed in P5 of this work.
- If the skill repeatedly nominates pass-through removals that break
  things, evaluate whether the deletion-test framing needs an
  AgenticApps-specific adapter (e.g. "deletion test, but consider the
  blast radius beyond the immediate caller graph").

## References

- Synthesis report §1 (mattpocock): `tooling-research-2026-05-02-batch2.md`
- Hand-off prompt Phase 3
- Live skills: `~/.claude/skills/mattpocock-improve-architecture/`,
  `~/.claude/skills/mattpocock-grill-with-docs/`
- Upstream: https://github.com/mattpocock/skills
- ADR-0010..0015 — context for why cross-PR drift is the gap left after
  Go routing, impeccable, database-sentinel, hooks
