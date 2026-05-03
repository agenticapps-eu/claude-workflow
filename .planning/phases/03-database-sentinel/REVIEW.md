# Phase 3 Review — database-sentinel integration

## Stage 1 — Spec compliance review (`gstack:/review`-equivalent)

**Reviewer:** primary agent (self), against action plan §2
**Diff scope:** templates/workflow-config.md (-1/+1 cso row), templates/config-hooks.json (+18 lines, two inserts), templates/claude-md-sections.md (-2/+8), docs/ENFORCEMENT-PLAN.md (+1 line), 2 new files (ADR template, ADR-0012)
**Method:** spec-drift check + JSON validity + adversarial read

### Spec drift check vs §2

| Patch | Spec match | Notes |
|---|---|---|
| 1: workflow-config.md `cso` row | ✅ Verbatim from §2 patch 1 | Old row replaced with the expanded version |
| 2: config-hooks.json `post_phase.security.sub_gates` | ✅ Verbatim from §2 patch 2 | Sub-gate inserted into existing security entry; comma + nesting correct |
| 3: claude-md-sections.md Hook 8 | ✅ + tightening | Spec text landed verbatim. Added cross-reference at the end: "...using the template at `templates/adr-db-security-acceptance.md`". Positive drift — connects the BLOCK-or-accept-via-ADR clause to the new template file Q3 produced |
| 4: ENFORCEMENT-PLAN.md row | ✅ Verbatim from §2 patch 4 | Inserted in Post-phase gates table after the verification-before-completion row |
| 5: config-hooks.json `finishing.db_pre_launch_audit` | ✅ Verbatim from §2 patch 5 | Inserted after `impeccable_audit`; comma + nesting correct |
| New: `templates/adr-db-security-acceptance.md` | ✅ Per Q3 + spec | Standalone file (per Q3 recommendation). Section content matches §2 verbatim. Added wrapper: when/why to use, time-boxed re-audit requirement, "compensating control must be verifiable" rule, one-acceptance-per-finding rule. These wrap the spec section without contradicting it — extends §2 by enforcing process rigor on acceptances. |

### Findings

| ID | Severity | Confidence | File:Line | Finding | Action |
|---|---|---|---|---|---|
| S1-1 | INFORMATIONAL | 8/10 | `templates/adr-db-security-acceptance.md` | The "Usage notes" section (time-box mandatory, compensating control must be concrete, one acceptance per finding, owner is a person) goes beyond what §2 specifies. §2 only gave the bare section template. | **NO ACTION** — these are guardrails on the spec template, not contradictions. The action plan §2 explicitly anticipates this acceptance pattern as a process; codifying the rules tightens the gate. ADR-0012 mentions this as "process overhead". |
| S1-2 | INFORMATIONAL | 9/10 | `templates/claude-md-sections.md` Hook 8 | Cross-reference to `templates/adr-db-security-acceptance.md` is added at end of the BLOCK-or-accept clause. §2 patch 3 doesn't include this reference. | **NO ACTION** — positive integration: the spec creates a template (per Q3) and the spec doesn't say where to mention it. Hook 8 is the obvious place because that's where the override mechanism is documented. |
| S1-3 | INFORMATIONAL | 7/10 | ADR-0012 | Cites three CVE numbers (2025-48757, 2025-14847, 2025-12819) in References. These come from the action plan §2 ("CVE-2025-48757 + 10 security studies") and the database-sentinel skill description. | **NO ACTION** — sourced from action plan + installed skill metadata; not invented. |

### Stage 1 verdict

**STATUS: clean.** Five patches landed verbatim from §2; new ADR template per Q3 with content matching the §2 section spec plus process guardrails; ADR-0012 documents decision with five rejected alternatives. JSON valid after both inserts.

---

## Stage 2 — Independent code-quality review

**Reviewer:** independent reviewer agent (Stage 2)
**Method:** patch-by-patch fidelity vs §2; JSON validity; cross-file scope/semantic consistency; ADR sourcing; hallucination check on flags + skill state.

### Verified

- `python3 -m json.tool` parses `templates/config-hooks.json` cleanly. `sub_gates` array placement is structurally correct (sibling of `evidence` inside `security`); commas land correctly around the new `db_pre_launch_audit` entry.
- All five §2 patches landed. Patches 1, 2, 4, 5 are byte-verbatim against the spec; Patch 3 adds a single `templates/adr-db-security-acceptance.md` cross-reference — defensible because the standalone template did not exist when §2 was written.
- `~/.claude/skills/database-sentinel/SKILL.md` is present (12k, MH-0 holds).
- Three CVE numbers in ADR-0012 are sourced from the installed SKILL.md frontmatter and `references/vibe-coding-context.md` reference (not invented).
- ADR template "Usage notes" extension (time-box, verifiable controls, one-per-finding, owner-is-person) is defensible: it tightens the gate without contradicting §2, and ADR-0012 explicitly accepts the resulting process overhead.

### Findings

<finding>
<id>S2-1</id>
<severity>Important</severity>
<confidence>85</confidence>
<file>templates/workflow-config.md:60</file>
<issue>Cross-file scope inconsistency. The Post-Phase `cso` row says `database-sentinel:audit (if Supabase touched)`, but `config-hooks.json` sub_gate trigger and Hook 8 / ENFORCEMENT-PLAN / ADR-0012 all use `supabase|postgres|mongodb`. The skill itself covers Supabase + MongoDB + Postgres + MySQL + Firebase. The narrow workflow-config row will mislead readers into believing Postgres / MongoDB phases skip the sub-gate.</issue>
<fix>Change the row's middle column to "`gstack:/cso` + `database-sentinel:audit` (if Supabase / Postgres / MongoDB touched)" so it matches the JSON trigger and Hook 8 wording. This matches §2 patch 1 verbatim — the spec does say "if Supabase touched", but the rest of the patches widened scope, so workflow-config.md is the lone outlier.</fix>
</finding>

<finding>
<id>S2-2</id>
<severity>Important</severity>
<confidence>88</confidence>
<file>templates/config-hooks.json:100</file>
<issue>Fabricated CLI flag. `db_pre_launch_audit.skill` is set to `database-sentinel:audit --full`. The upstream skill (SKILL.md at `~/.claude/skills/database-sentinel/`) has no `--full` flag — it is a natural-language-invoked Claude Skill ("audit my database"), not a CLI tool with subcommands. Grep for `--full` in SKILL.md returns zero hits. The `_note` field in this same JSON disclaims that the orchestrator does not execute these strings today, but the string still leaks into ADR-0012 ("run `database-sentinel:audit --full`") and reads as a real, executable invocation. Future readers will look for a flag that does not exist.</issue>
<fix>Either (a) drop the `--full` suffix and rely on prose in the `evidence` / Hook docs to say "full-scope audit, not phase-scoped" (recommended — keeps the skill string consistent with `post_phase.security.sub_gates[0].skill`), or (b) define what "full" means in skill terms (e.g. "audit all backends in scope", "include MongoBleed probe"), and document the convention in ADR-0012 + the skill so the flag is at least a project-level pseudo-flag rather than an apparent-but-absent upstream flag. §2 patch 5 specifies `--full`, so deviating is a spec-fidelity tradeoff vs hallucination — call this out explicitly in ADR-0012 if keeping it.</fix>
</finding>

<finding>
<id>S2-3</id>
<severity>Important</severity>
<confidence>80</confidence>
<file>templates/config-hooks.json:74; docs/ENFORCEMENT-PLAN.md:67</file>
<issue>BLOCK-on-Critical/High semantic is not consistent across files. Hook 8, ADR template, and ADR-0012 all use the strong word "BLOCK branch close." JSON sub_gate evidence ("all High and Critical findings resolved or acknowledged in ADR") and the ENFORCEMENT-PLAN row ("Critical / High findings resolved or recorded in ADR") describe the same outcome but never use the word "block." workflow-config.md does not mention blocking semantics at all. Readers who only consult the JSON or ENFORCEMENT-PLAN will perceive an advisory gate; readers of Hook 8 will perceive a hard block.</issue>
<fix>Add an explicit blocking phrase to the JSON `evidence` (e.g. "...resolved or acknowledged in ADR; otherwise BLOCKS branch close") and to the ENFORCEMENT-PLAN row's evidence column. Optional but cheap: add "BLOCK on Critical/High" to the workflow-config.md row's "What it does" column.</fix>
</finding>

### Stage 2 verdict

**Status: minor-fix required.** The five patches landed; JSON is valid; ADR-0012 alternatives are genuine and CVE references are sourced from the installed skill. Three real cross-file consistency issues — narrow scope in workflow-config.md (S2-1), the `--full` flag that does not exist upstream (S2-2), and inconsistent BLOCK-vs-soft-evidence wording (S2-3) — should be addressed before Phase 3 closes. None blocks merge of the worktree, but all three will mislead future readers.

### Resolution (post-Stage-2 fixes applied)

All three findings fixed before commit:

- **S2-1 (scope inconsistency):** `templates/workflow-config.md` cso row widened from "(if Supabase touched)" to "(if Supabase / Postgres / MongoDB touched)" to match the JSON sub-gate trigger and Hook 8 / ENFORCEMENT-PLAN wording. Spec-deviation: §2 patch 1 narrowed the workflow-config row to Supabase only — corrected to align with the rest of the patch set, since the database-sentinel skill itself supports all three backends.
- **S2-2 (`--full` flag):** Dropped from `templates/config-hooks.json` `db_pre_launch_audit.skill`. Added a new `scope` JSON field (`"full — audit every supported backend in the project, not phase-scoped"`) to convey the intent in schema rather than via a fabricated CLI flag. ADR-0012 line 41 updated to drop the flag in the running text. New "Spec deviation" entry added to ADR-0012 Follow-ups, transparently noting that §2 patch 5 specified `--full` and explaining why the patch was applied without it.
- **S2-3 (BLOCK semantic inconsistency):** Added explicit "otherwise BLOCKS branch close" / "otherwise BLOCKS launch" phrasing to: `config-hooks.json` sub-gate evidence, `config-hooks.json` `db_pre_launch_audit` evidence, `ENFORCEMENT-PLAN.md` row evidence, and `workflow-config.md` cso row "What it does" column. All five files now consistently signal blocking semantics.

**Verification re-run after fixes:** `jq empty templates/config-hooks.json` still passes; sub_gates and finishing entries inspected with `jq`; greps confirm BLOCK phrasing in all 4 target files; `--full` references in repo are now scoped to the spec-deviation note in ADR-0012.

**FINAL STATUS: Stage 1 ✅, Stage 2 ✅ (after 3-fix resolution). Phase 3 ready to commit.**
