# Superpowers Enforcement Plan

> **Status:** Active contract. Every AgenticApps project using this workflow MUST
> honor the commitments in this document. This is not documentation — it is
> enforcement.

**This file is the single hook-bindings table required by spec §09 item 3.**
Other files reference it; they do not restate bindings.

## Why this file exists

The `.planning/config.json` hooks block declares intent. It is NOT read by any GSD
workflow, so flags like `hooks.pre_phase.brainstorm_ui=true` do not cause any skill
to fire. In practice, Superpowers skills (`brainstorming`, `test-driven-development`,
`verification-before-completion`, `requesting-code-review`, `systematic-debugging`)
get skipped across entire projects without the developer noticing.

This document closes that gap using three layered enforcement mechanisms, each
derived from the persuasion principles Cialdini + Wharton + Vincent (Superpowers)
proved work on LLMs:

1. **Authority layer** — `CLAUDE.md` uses MUST / non-negotiable / NO EXCEPTIONS
   language for every Superpowers invocation. Suggestive phrasing removed.
2. **Commitment layer** — The `agentic-apps-workflow` skill, when it activates,
   emits a commitment block naming the Superpowers skills it will invoke and in
   what order. Once stated, the agent is psychologically anchored.
3. **Rationalization layer** — Pre-written rebuttals for the 9 specific excuses
   LLMs generate when they want to skip discipline, plus 13 red flags that
   trigger an automatic stop-and-restart.

Together these produce the same effect the articles describe: the agent
self-corrects when it catches itself drifting, because drift would contradict its
own stated commitment.

## Gate-to-skill mapping (the hook-bindings table)

This is the authoritative mapping of core spec §02 gates to required Superpowers
(and gstack) skill invocations. Each row is a commitment — if the trigger fires,
you MUST invoke the bound skill and produce the evidence.

**Gate** is the canonical §02 name and is normative: §02 forbids renaming a gate
or merging two gates into one, so every gate below gets exactly one row.
**Host key** is this host's own identifier for the same gate in
`.planning/config.json` → `hooks` (seeded from `templates/config-hooks.json`) —
host-specific data, not a second name for the gate. Where the two differ, the
canonical name wins in any conformance discussion.

All 16 gates below have a binding: every gate's trigger condition can occur in
the project type this workflow scaffolds (a full-stack product repo). Gates
whose trigger cannot occur in a *given* project — `database-security` and
`db-pre-launch-audit` in a repo with no database, the UI gates in a repo with
no frontend — are inert there by their own trigger, which is not the same as
being unbound. For gates whose trigger cannot occur in **this scaffolder
repo itself**, see the "Spec deltas" section of `skill/SKILL.md`.

### Pre-phase gates

| Gate (§02) | Host key | Trigger | Bound skill | Required evidence |
|---|---|---|---|---|
| `brainstorm-ui` | `brainstorm_ui` | Phase has ≥1 plan introducing/modifying a frontend component, route, or visual surface, AND no prior CONTEXT.md "Design alternatives" section for this UI scope | `superpowers:brainstorming` | CONTEXT.md section listing ≥2 named UI alternatives with trade-offs |
| `brainstorm-architecture` | `brainstorm_architecture` | Phase has ≥1 plan introducing a new service, model, integration, or data shape, AND no prior CONTEXT.md/RESEARCH.md "Architecture alternatives" section for this scope | `superpowers:brainstorming` | RESEARCH.md or CONTEXT.md with ≥2 named architectural alternatives with trade-offs |
| `design-shotgun` | `design_shotgun` | Phase has ≥1 UI plan AND no UI-SPEC.md exists for the surface being built (`ui_hint_yes && no_ui_spec_yet`) | gstack `/design-shotgun` (generation) + gstack `/browse` (preview) | ≥3 rendered visual variants referenced from CONTEXT.md or UI-SPEC.md, with the user's chosen variant marked |
| `design-critique` | `design_critique` | A UI plan with an **existing** UI-SPEC.md, before implementation begins (`ui_hint_yes && ui_spec_exists`) | `impeccable:critique` | Critique document referenced from the phase artifacts naming ≥1 specific design issue and its remediation |

### Pre-execution gate

| Gate (§02) | Host key | Trigger | Bound skill | Required evidence |
|---|---|---|---|---|
| `plan-review` | `multi_ai_plan_review` | After a phase's `*-PLAN.md` exist and before the first code-touching execution edit — UNLESS a `*-SUMMARY.md` exists for the resolved phase (grandfathered) | `/gsd-review`, enforced programmatically by `.claude/hooks/multi-ai-review-gate.sh` | `{padded_phase}-REVIEWS.md` in the phase directory with independent output from ≥2 external AI reviewer CLIs |

Override: `GSD_SKIP_REVIEWS=1` or a `.planning/current-phase/multi-ai-review-skipped`
sentinel. Skipping requires an explicit override per ADR-0018; the resolver and
grandfather rule are specified in ADR-0025.

### Per-task / execution gates

| Gate (§02) | Host key | Trigger | Bound skill | Required evidence |
|---|---|---|---|---|
| `tdd` | `tdd_enforcement` | Any task marked `tdd="true"` whose changeset includes logic verifiable by automated test | `superpowers:test-driven-development`; additionally `ts-declare-first` when the task introduces a new TypeScript module (spec §13) | Atomic commit pair `test(RED): <desc>` → `feat(GREEN): <desc>`; optional trailing `refactor:` |
| `ui-preview` | `ui_preview` | A task modifying any frontend component, route, or visual surface, before that task's commit lands | gstack `/browse` + screenshot against a running dev server | Screenshot path (or browser artifact reference) in the commit message or SUMMARY.md |
| `verification` | `verification_before_done` | Before any task is marked complete (before any `TaskUpdate --completed` or equivalent state transition) | `superpowers:verification-before-completion` | ≥1 piece of on-disk evidence per `must_have` in VERIFICATION.md (grep, test output, curl, screenshot), posted BEFORE the status change |

`ts-declare-first` is bound to `tdd` by explicit invocation only; its §13
implicit trigger is not wired — see the "Spec deltas" section of `skill/SKILL.md`.

### Post-phase gates

| Gate (§02) | Host key | Trigger | Bound skill | Required evidence |
|---|---|---|---|---|
| `spec-review` | `spec_review` | After all execution tasks complete, before phase verification (always) | gstack `/review` | REVIEW.md "Stage 1 — Spec compliance" section: spec drift, missing `must_have` coverage, protocol-violation flags |
| `code-review` | `code_quality_review` | After `spec-review` completes, before phase verification (always) | `superpowers:requesting-code-review` | REVIEW.md "Stage 2 — Code quality" section authored by an independent reviewer agent in a fresh context |
| `security` | `security` | Changeset touches authentication, storage, request handling, secret material, or LLM trust boundaries | gstack `/cso`; §14 evidence via `injection-guard` (agenticapps-observability) on LLM-scoped phases | SECURITY.md referenced from VERIFICATION.md, listing audited threat models + mitigation evidence; on LLM prompt-building paths it MUST also record §14 conformance evidence |
| `database-security` | `security.sub_gates[0]` | Changeset touches database schema, RLS rules, security definer functions, or storage policies | `database-sentinel:audit` | DB-AUDIT.md referenced from SECURITY.md or VERIFICATION.md; Critical/High findings resolved or accepted via `templates/adr-db-security-acceptance.md`; otherwise BLOCKS branch close |
| `qa` | `qa` | Phase ships user-visible behavior AND a dev server is reachable on a known local port | gstack `/qa` | QA report file or URL referenced from VERIFICATION.md, with ≥1 live-app interaction logged |
| `impeccable-audit` | `impeccable_audit` | Changeset modifies the visual surface of a shipping UI (typography, color, layout, spacing, motion). MAY also be invoked retroactively | `impeccable:audit` | Impeccable-audit report referenced from REVIEW.md or VERIFICATION.md; no unresolved Red findings |
| `db-pre-launch-audit` | `db_pre_launch_audit` | Before the project's first production launch, and after any major DB migration | `database-sentinel:audit`, full scope (every supported backend in the project, not phase-scoped) | Pre-launch DB-AUDIT.md referenced from a launch-readiness artifact (SECURITY.md / RELEASE.md), zero Critical and zero High findings; otherwise BLOCKS launch |

`database-security` is a gate in its own right, not a sub-case of `security`:
§02 forbids merging two gates into one. Its host key is nested under `security`
in `config.json` for historical reasons — that nesting is host data and carries
no conformance meaning. `db-pre-launch-audit` binds the same skill as
`database-security` but is a distinct gate with a distinct trigger and a
distinct evidence artifact.

### Finishing gate

| Gate (§02) | Host key | Trigger | Bound skill | Required evidence |
|---|---|---|---|---|
| `branch-close` | `branch_close` | Feature branch is ready to merge | `superpowers:finishing-a-development-branch` | PR description summarizing shipped scope, linking phase artifacts (CONTEXT.md, PLAN.md, VERIFICATION.md, REVIEW.md), and documenting remaining `should_have` gaps |

### Host extension gates (beyond the §02 list)

§02 permits additional host-specific gates. These are **not** canonical §02
gates and carry no conformance weight:

| Host key | Trigger | Bound skill | Evidence | Status |
|---|---|---|---|---|
| `writing_plans` | `/gsd-plan-phase {N}`, once plans are drafted (always) | `superpowers:writing-plans` | PLAN.md frontmatter includes `written_via: superpowers:writing-plans` | Active |
| `systematic_debugging` | Any unexpected failure mid-phase, or `/gsd-debug` invoked | `superpowers:systematic-debugging` | Root-cause write-up (Observe → Hypothesize → Test → Conclude) in the phase directory before any fix commit | Active |
| `observability_scan` | `.observability/baseline.json` present (project adopted §10.9 enforcement) | `observability:scan` | `.observability/delta.json`; advisory warning when `counts.high_confidence_gaps > 0` | **Advisory, agent-invoked.** Run as the post-phase step `/observability scan --since-commit <phase-base>` per CLAUDE.md — not a `settings.json` lifecycle hook. The scan belongs to the standalone `agenticapps-observability` skill, which has owned this surface since 2.0.0; migration `0018` here is a tombstone. This repo shipped a dead `observability-postphase-scan.sh` (registered in no event, so it never fired) until 2.5.0, which removed it — see ADR-0040. |

### Language-specific code-quality gates (extension of post-phase Stage 2)

These gates extend Stage 2 (`superpowers:requesting-code-review`) with language-specific
linter packs. They fire only when the phase touches files in the matching language.

| GSD step | Required skill | Trigger | Evidence |
|---|---|---|---|
| Stage 2 review on Go phase | `samber:cc-skills-golang` linter checks (modernize, errors, testing, security pack) | Phase touches `*.go` | Stage 2 REVIEW.md cites which Go skills fired |
| Resilience-touching Go phase | `netresearch:go-development-skill` checks (retry, graceful shutdown, observability) | Phase introduces or modifies a long-running service, scheduler, or external call | Resilience checklist appended to REVIEW.md |
| Stage 2 review on TS/React phase | `QuantumLynx:ts-react-linter-driven-development` (`@pre-commit-review` + `@refactoring`) | Phase touches `*.tsx`/`*.ts` | SonarJS thresholds passed (cognitive ≤15, cyclomatic ≤10, function ≤200 lines, file ≤600), Red findings resolved |

### Finishing gates

| GSD step | Required skill | Trigger | Evidence |
|---|---|---|---|
| Feature branch ready to merge | `superpowers:finishing-a-development-branch` | Always | PR description lists skills invoked, gates passed, evidence links |

## Two-layer enforcement: programmatic + conceptual

The gate-to-skill mapping above describes the **conceptual** enforcement layer:
prose in CLAUDE.md + the commitment ritual + skill invocations. This works
while the session is fresh, but degrades silently on compaction or cold-start.

The **programmatic** layer is shell scripts (or prompt-type sub-agents) that
fire on Claude Code's hook events with deterministic exit codes. Exit code 2
truly blocks the triggering tool call; exit code 1 only logs a warning. The
two layers compose: programmatic for *gates that must never be overridden*;
conceptual for *intent and skill routing*.

| Layer | Enforces | How | Failure mode |
|---|---|---|---|
| **Conceptual** | Which skill fires when, how phases sequence, the commitment ritual | CLAUDE.md prose + Cialdini commitment | Compaction degrades context; prose drifts |
| **Programmatic** | Tool-level deterministic gates (DB safety, design preflight, premature stop, audit log) | `PreToolUse` / `PostToolUse` / `Stop` / `SessionStart` shell scripts with `exit 2` | Latency budget per `PreToolUse` invocation (~100ms); schema lock-in |

### Programmatic hooks (9 project-scoped + 1 global)

Every row below is registered in a `settings.json` and therefore actually
fires. A hook script on disk that appears in no `settings.json` event is a
**dead hook** and is not listed here — `bin/check-hooks.sh` reports it as a
failure (see "Verifying hook installation").

| Hook | Event | Matcher | What it enforces | Override |
|---|---|---|---|---|
| **1 Database Sentinel** | `PreToolUse` | `Bash\|Edit\|Write` | Blocks `DROP/TRUNCATE TABLE`, `DELETE` without `WHERE`, edits to `.env*`, edits to `migrations/*` without phase approval | `touch .planning/current-phase/migrations-approved` for migrations; ADR with explicit acceptance for SQL |
| **2 Design Shotgun Gate** | `PreToolUse` | `Edit\|Write` | Blocks edits to `*.tsx`/`*.css`/`design/`/`src/components/` without preflight sentinel | Run `/design-shotgun`; or `touch .planning/current-phase/design-shotgun-passed` for one-off (document override in commit) |
| **3 Phase Sentinel** | `Stop` | (none) | Deterministic shell check of `.planning/current-phase/checklist.md`; blocks `Stop` if items remain. (Migration `0022` replaced the earlier Haiku prompt-type hook with this `type: command` hook.) | Mark items complete or update the checklist before retry |
| **4a Skill Router Audit Log** | `PostToolUse` | `mcp__skills__.*\|Bash` | Logs every skill invocation as JSONL to `.planning/skill-observations/skill-router-{date}.jsonl` | Informational only; no blocking |
| **4b Session Bootstrap** | `SessionStart` | (none) | Surfaces the last 20 skill invocations on each new session | Informational only; no blocking |
| **5 Commitment Re-Injector** | `SessionStart` | `compact` | Re-injects `head -50 CLAUDE.md` + current-phase `COMMITMENT.md` after compaction | Informational only; no blocking. **GLOBAL** (cwd-aware, no-ops on non-AgenticApps projects) |
| **6 Normalize CLAUDE.md** | `PostToolUse` | `Edit\|Write\|MultiEdit` | Re-normalizes `CLAUDE.md` section order/shape after any edit (migration `0010`) | Informational only; no blocking |
| **7 OpenSpec Change Gate** | `PreToolUse` | `Edit\|Write\|MultiEdit\|NotebookEdit` | Spec §18. Under an active OpenSpec change, blocks code edits unless `openspec validate --all` is green **AND** `changes/<slug>/REVIEWS.md` carries ≥2 reviewers. No active change → allow; `openspec/**` writes → exempt; malformed stdin → fail open. The project hook is a shim onto `~/.agenticapps/bin/openspec-change-gate.sh`; the same script runs as a git `pre-commit` hook and in CI, which is the real guarantee. Retarget of the 0.x plan-review gate (ADR-0018 → ADR-0044) | `GSD_SKIP_REVIEWS=1` (logged). `OPENSPEC_GATE_STRICT=1` opts into the stricter "no code without a change" posture |
| **Architecture Audit Check** | `SessionStart` | (none) | Nags when the last architecture audit is > 7 days old | Informational only; no blocking |

> **Retired — 8 GitNexus Background Reindex** (`PostToolUse`/`Bash`, migration
> `0026`, ADR-0039). GitNexus was removed from the workflow in v3.0.0
> (ADR-0044); migration `0032` unregisters the hook and deletes the engine.
> Migrations `0026`/`0029`/`0031` and ADR-0039 are retained as history
> (§08 supersede-don't-delete) — they are still the replay path for a project
> upgrading from a pre-3.0.0 version.

The hooks split between two install locations:

- **The 8 project-scoped hooks** (1–4b, 6, 7, and the architecture audit check)
  live at `.claude/hooks/<name>.sh` and are registered in the project's
  `.claude/settings.json`. Installed during `/setup-agenticapps-workflow` from
  the snapshot's `hooks/` directory (built from `templates/.claude/hooks/`) and
  the `templates/claude-settings.json` template.
- **Hook 5** is global: lives at `~/.claude/hooks/commitment-reinject.sh`
  and is registered in `~/.claude/settings.json` with `matcher: compact`.
  cwd-aware — no-ops on non-AgenticApps projects.

### Verifying hook installation

In any AgenticApps project, run:

```bash
~/.claude/skills/agenticapps-workflow/bin/check-hooks.sh
```

The expected hook set is **derived from the project's own `settings.json`**,
never hardcoded, so a newly registered hook cannot escape verification
(ADR-0040). It reports `✓`/`✗` for three things: every registered hook is
present and executable; every hook is bound to a lifecycle event, with the
load-bearing gates asserted against their expected event; and every hook script
on disk is registered somewhere (a script that is not is a dead hook). Exit 0
when all checks pass, exit 1 otherwise.

### Why programmatic + conceptual instead of programmatic-only

Sah and Damle's articles correctly identify that programmatic hooks fire
deterministically while prose discipline degrades. But the commitment
principle (Cialdini; Wharton GAIL 2025) only works because the agent
**states** the commitment publicly and **listens** to its own statement.
Replacing the prose layer with hooks alone would dissolve the commitment
binding — you'd have enforcement without consistency.

The split rule: **if a violation costs you a phase iteration → programmatic
hook. If it's a routing/intent question → prose.** Both layers must be
present.

## The commitment ritual

When `agentic-apps-workflow` activates, the agent MUST emit this block as its
first output text — before any tool call, before any clarifying question:

```
## Workflow commitment

I am using the agentic-apps-workflow skill for this task.
Task scope: {brief description}
Task size: {tiny | small | medium | large}

Skills I will invoke, in order:
1. {skill-name} — {why}
2. {skill-name} — {why}
...

Post-phase gates (if applicable): {review | cso | qa}
Verification evidence I will produce: {list}

Once I have stated this plan, I am committed to it.
Deviating without explicit user approval is a protocol violation.
```

This is the foot-in-the-door from the Wharton paper. Skipping it is itself a
protocol violation.

## Rationalization table

Pattern-match your own reasoning against these. If you think one of the "AI
thinks" statements, apply the reality check BEFORE acting.

| The AI thinks... | The reality is... |
|---|---|
| "This is just a simple change, skip brainstorming" | Simple changes produce the majority of outages. Brainstorming takes 2 minutes. |
| "TDD slows me down on this" | TDD is faster than debugging a silent regression in production. |
| "I'll add tests after the implementation" | Tests-after verify what was built, not what was needed. Sunk-cost trap — write the failing test first. |
| "The existing tests cover this" | Verify that claim: run the tests, check coverage for the modified lines, or write a new failing test proving the current suite misses the change. |
| "I already manually verified it works" | Manual testing is not systematic, not repeatable, not in CI. It is not verification. |
| "The design is obvious, no need for brainstorming" | The design *feels* obvious because you haven't listed alternatives yet. List at least 2. |
| "Running /review is overkill for this PR" | `/review` finds structural issues tests miss. It runs in 60s. Run it. |
| "The user said skip tests because it's urgent" | Acknowledge urgency, explain risk, offer a minimal focused test for the critical path. Never silently comply. |
| "I've already written 300 lines, adding tests now is wasteful" | Sunk cost. Either delete-and-TDD or accept that the 300 lines are unverified debt and say so in the commit. |
| "This task isn't complex enough to invoke agentic-apps-workflow" | The skill description says it triggers on ANY code change. Invoke it. |

## 13 red flags (from Superpowers TDD skill, adapted)

Encountering any of these triggers an automatic **STOP → DELETE → RESTART with
discipline** sequence. This is non-negotiable.

1. Code written before the test (for `tdd="true"` tasks)
2. Test added after implementation (same)
3. Test passes on first run — no RED stage observed
4. Cannot explain why the test should have failed
5. Tests marked for "later" addition
6. Any sentence starting with "just this once"
7. Claims of manual testing completion as verification evidence
8. Two-stage review collapsed into one review
9. Framing TDD or brainstorming as "ritual" or "ceremony"
10. Keeping pre-written implementation as "reference" while writing tests
11. Sunk-cost reasoning about deleting unverified code
12. Describing discipline as "dogmatic" or "slowing us down"
13. Any sentence starting with "This case is different because..."

## Pressure-test scenarios

The workflow MUST survive each of these without degrading. If the agent fails
any scenario in live development, update CLAUDE.md + this document to close
the loophole.

### Scenario 1 — Time pressure + confidence
> Production incident. $5,000/min losses. You know the fix and can ship in
> 5 minutes without running the workflow. Running the workflow adds 2 minutes.

**Correct response:** Invoke `superpowers:systematic-debugging` first.
Root-cause protocol prevents deploying a symptom fix that worsens the outage.
The 2-minute cost is dwarfed by the risk of rollback-worse-than-original.

### Scenario 2 — Sunk cost + working code
> You spent 45 minutes writing a feature that passes manual review. You then
> notice `superpowers:test-driven-development` should have gated this.

**Correct response:** Delete the implementation. Write the failing test first.
Re-implement. The 45 minutes are a sunk cost; the untested code is technical
debt that will cost more to debug later.

### Scenario 3 — User authority override
> The user says: "Skip tests, just ship it, we can add tests later."

**Correct response:** Acknowledge the urgency. Explain the regression risk
one sentence. Offer minimal focused tests covering the critical path. If the
user explicitly confirms "skip them entirely," comply but record the override
in the commit message as `NO-TESTS-PER-USER-REQUEST: <reason>` so the
technical debt is tracked.

### Scenario 4 — Small task rationalization
> "This is a one-line change to a config file, surely the full workflow is
> overkill."

**Correct response:** The rationalization table calls this out explicitly.
Invoke the workflow. Config changes cause more outages than code changes.
Minimum: state the change, verify it in the running system, commit atomically.

### Scenario 5 — Phase seems purely UI, no backend implications
> "Phase N is 100% frontend. TDD is impractical. Skip it."

**Correct response:** TDD is modified for frontend work (component snapshot
tests, visual regression via `/browse`), not skipped. The test is the
screenshot diff. `ui_preview` hook is still mandatory.

## How to verify enforcement is working

After any phase completes, run this check:

```bash
# 1. Commitment block was emitted
grep -r "## Workflow commitment" .planning/phases/{padded_phase}-*/ 2>/dev/null

# 2. Every TDD task produced RED + GREEN commit pair
git log --oneline {phase_base}..HEAD | grep -E "^[a-f0-9]+ (test|feat)\(" | wc -l

# 3. Two-stage review evidence
test -f .planning/phases/{padded_phase}-*/REVIEW.md && \
  grep -q "Stage 2" .planning/phases/{padded_phase}-*/REVIEW.md

# 4. Verification evidence for must_haves
grep "^- \*\*Evidence" .planning/phases/{padded_phase}-*/VERIFICATION.md | wc -l
```

If any check fails, the phase did NOT honor the enforcement plan. File this
as a process bug, not a feature bug — update the enforcement document, not
just the phase.

## Config.json hooks — the seed, not a second table

The `hooks` block in a project's `.planning/config.json` names the same gates
in skill-named (not flag-based) form. It is **declarative intent only**: no
orchestrator code reads it today — the skill + CLAUDE.md layer does. It exists
so the enforcement layer can become data-driven without a schema migration.

The canonical seed is `templates/config-hooks.json` in this repo (installed to
`.planning/config.json` by `/setup-agenticapps-workflow`). Read it there rather
than from a copy pasted here: an inline duplicate of the block is exactly the
kind of second, silently-drifting bindings table this file exists to replace.
The `Host key` column of the table above is the index into it.

Its `_note` field states the same caveat at the point of use, and its
`_enforcement_contract` field points back to this file.

## When to update this plan

- A pressure test fails in live development → add a new rationalization row
  AND update the failing scenario's "Correct response"
- A new Superpowers skill becomes available → add it to the gate mapping
- A GSD workflow step changes → update the gate-to-skill mapping
- A gstack command is renamed → update references

This document is code. Version it. Review changes in PRs. Never let it rot.
