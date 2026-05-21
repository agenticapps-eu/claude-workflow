# P3 — §12 Mermaid Audit Log

Audit of host SKILL.md files for spec §12 "Branchy workflows"
conformance. §12 trigger: paragraph has ≥2 decision branches AND
≥1 cycle/fallback path.

§12 conformance rule applied here:

- **MUST satisfy** the SHOULD-level convention in every host
  SKILL.md / AGENTS.md / contract spec file **newly authored at or
  after 0.4.0 adoption**.
- **MAY** convert pre-existing files opportunistically at the
  host's next significant rewrite. **Bulk conversion is not
  required.**

Practical application here:

- `ts-declare-first/SKILL.md` — newly authored in commit `9c90b14`
  at 0.4.0 adoption. MUST satisfy §12. → audit + convert this PR.
- `skill/SKILL.md` — pre-existing (last significant rewrite was
  pre-0.4.0). MAY convert opportunistically. → audit + defer per
  §12's bulk-conversion waiver.
- `add-observability/SKILL.md` — pre-existing (last significant
  rewrite was v0.3.x). MAY convert opportunistically. → audit +
  defer.
- `templates/**/SKILL.md` — none exist; nothing to audit.

This file is the audit-trail evidence for the deferral decisions
on the pre-existing files. If a future PR materially rewrites
either of them, that PR's author SHOULD revisit these candidates
and apply the conversion.

---

## File 1: `ts-declare-first/SKILL.md` — NEW (MUST audit + convert)

### Candidates

| Section | Line range (post-vendor) | ≥2 branches | Cycle/fallback | §12 Decision |
|---------|--------------------------|-------------|----------------|--------------|
| Trigger (explicit/implicit) | ~31-48 | yes (2 trigger forms) | no (parallel options, not runtime routing) | KEEP — parallel-options shape, not branchy workflow |
| Procedure Phase 1/2/3 | ~50-170 | yes (3 phases) | partial (Phase 2 → Phase 1 on declaration error during type-check) | KEEP — primarily sequential discipline, Mermaid would obscure ordering |
| Phase 2 resolution-mechanism options | ~107-125 | yes (3 options) | no | KEEP — host-choice options, not runtime routing |
| **Refusals** | ~190-208 | **yes (3 refusal triggers)** | **yes (each refusal reroutes operator back to the relevant phase — cycle)** | **CONVERT** |

### Conversion: Refusals section

The Refusals section is the only §12 trigger in `ts-declare-first/
SKILL.md`. Three refusal conditions are checked concurrently when
the skill is invoked; any triggering refusal routes the operator
back to the relevant phase with specific recovery instructions.

Conversion plan:

- Add `flowchart TD` Mermaid block at the top of the Refusals
  section.
- Nodes: `invoke` (start), `check` (the three concurrent
  integrity checks), three `refuse_*` nodes (one per refusal
  condition), `proceed` (all checks pass).
- Cycles: each `refuse_*` node routes back to `check` (operator
  fixes the issue, skill re-checks).
- Retained prose: each refusal's specific recovery instruction
  (the judgment the diagram can't encode — *why* this paragraph
  exists, *what* the operator does to recover).

Applied in commit landing this audit log. See SKILL.md "Refusals"
section in the same commit for the rendered diagram + prose.

### Other audit findings (no conversion needed)

The "When to use it / When NOT to use it" pair in `README.md` was
considered but README.md is operator-facing documentation, not the
skill prompt itself. §12's audit scope is SKILL.md / AGENTS.md /
contract spec files. README is excluded.

---

## File 2: `skill/SKILL.md` — pre-existing (audit only; defer)

Pre-existing at version 1.12.0; §12 bulk-conversion waiver applies.
Audit candidates documented for future opportunistic conversion.

| Section | Line range | ≥2 branches | Cycle/fallback | §12 trigger? | Defer reason |
|---------|------------|-------------|----------------|--------------|--------------|
| Step 1 task-size table (tiny/small/medium/large) | 56-62 | yes (4 sizes) | no | no | not a §12 trigger |
| Step 2 GSD entry-point routing | 64-76 | yes (5 entry points) | yes ("STOP, either invoke or state out-of-scope" — fallback) | **YES** | Pre-existing file; defer per §12 bulk-conversion waiver |
| Step 3 gate-to-skill map | 78-120 | yes (many gates) | partial (post-phase gates re-run on failure) | partial | Defer — primarily sequential, Mermaid would be sprawling |
| Rationalization Table | 144-156 | yes (8 rationalizations) | no (parallel options, no flow) | no | KEEP regardless — pure judgment-prose table |
| 14 Red Flags (STOP→DELETE→RESTART) | 157-172 | yes (14 triggers) | yes (RESTART is conceptual cycle) | marginal | Defer — the cycle is conceptual, not literal; KEEP probably appropriate even at conversion time |
| Verification Check (after phase completes) | 183-207 | yes (5 commands) | yes ("If any check fails, file as process bug, update enforcement-plan, re-run") | **YES** | Pre-existing file; defer per §12 bulk-conversion waiver |
| Daily Quick Reference | 209-217 | no (7-step sequence) | no | no | KEEP — sequential checklist |

Two strong CONVERT candidates if a future PR materially rewrites
this file: **Step 2 GSD entry-point routing** and **Verification
Check**. Both have explicit fallback paths and the §12 SHOULD would
genuinely improve them.

---

## File 3: `add-observability/SKILL.md` — pre-existing (audit only; defer)

Pre-existing at version 0.4.0; §12 bulk-conversion waiver applies.
Audit candidates documented for future opportunistic conversion.

| Section | Line range | ≥2 branches | Cycle/fallback | §12 trigger? | Defer reason |
|---------|------------|-------------|----------------|--------------|--------------|
| Dispatch table (init/scan/scan-apply) | 55-67 | yes (3 subcommands) | yes ("If subcommand omitted, default to scan" — fallback) | **YES** | Pre-existing file; defer per §12 bulk-conversion waiver |
| Routing-table structural invariant | 69-92 | no (single-branch invariant + verification script) | no | no | KEEP — judgment-heavy, no branching |
| Resolution rules (§10.7.1) | 94-99 | no | no | no | KEEP |
| Stack templates table | 101-116 | yes (5 stacks) | no | no | KEEP — selection table, not branchy workflow |
| Conformance with §10.7 | 118-130 | no (4 requirements in parallel) | no | no | KEEP |
| When to invoke table | 132-143 | yes (4 intents) | no | no | KEEP — intent→subcommand routing, no cycle |

One strong CONVERT candidate if a future PR materially rewrites
this file: **Dispatch table** (subcommand routing with fallback to
`scan` on omitted argument).

The init subcommand's own procedure (9 phases, 3 consent gates,
described in `./init/INIT.md`) is OUT OF SCOPE here — that file is
not in our audit set (PLAN.md P3 bounded the audit to host SKILL.md
files plus templates). If the bounded audit expands in a future
phase, INIT.md is the highest-value §12 conversion target in the
add-observability skill.

---

## Summary

- **Convert (this PR)**: 1 paragraph in `ts-declare-first/SKILL.md`
  (Refusals section).
- **Defer (per §12 bulk-conversion waiver)**: 4 candidate
  paragraphs across pre-existing files (Step 2 GSD entry-point
  routing in skill/SKILL.md, Verification Check in skill/SKILL.md,
  Dispatch table in add-observability/SKILL.md, plus the marginal
  14-Red-Flags candidate in skill/SKILL.md).
- **KEEP (no conversion appropriate even on opportunity)**: ~10
  paragraphs across all three files — primarily judgment tables,
  sequential checklists, and parallel-options content where the
  table format already conveys the structure.

Future PRs materially rewriting any of the pre-existing files SHOULD
revisit this log and apply the deferred conversions per §12's
SHOULD-level convention.

## Audit boundary

Per PLAN.md P3.4: audit bounded to host SKILL.md files + templates.
No `templates/**/SKILL.md` exist. Deeper instruction files (e.g.
`add-observability/init/INIT.md`, `add-observability/scan/SCAN.md`,
`add-observability/scan-apply/APPLY.md`) are out of scope here but
noted as future-audit candidates in the §12 trail.
