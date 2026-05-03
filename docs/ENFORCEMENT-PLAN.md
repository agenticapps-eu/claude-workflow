# Superpowers Enforcement Plan

> **Status:** Active contract. Every AgenticApps project using this workflow MUST
> honor the commitments in this document. This is not documentation — it is
> enforcement.

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

## Gate-to-skill mapping

This is the authoritative mapping of GSD workflow steps to required Superpowers
(and gstack) skill invocations. Each row is a commitment — if you run the
GSD step, you MUST invoke the mapped skill.

### Phase planning gates

| GSD step | Required Superpowers / gstack skill | Trigger | Evidence of invocation |
|---|---|---|---|
| `/gsd-discuss-phase {N}` | `superpowers:brainstorming` | Always, before the first discuss question | Design doc section in CONTEXT.md listing alternatives explored |
| `/gsd-plan-phase {N}` (UI hint: yes) | gstack `/design-shotgun` or `/design-consultation` | Phase has frontend indicators | UI-SPEC.md references generated variant paths + user's pick |
| `/gsd-plan-phase {N}` (new service/model) | `superpowers:brainstorming` | Phase introduces new backend service, data model, or integration | RESEARCH.md has "Alternatives considered" section with ≥2 options |
| `/gsd-plan-phase {N}` (always) | `superpowers:writing-plans` | Always, once plans are drafted | PLAN.md frontmatter includes `written_via: superpowers:writing-plans` |
| `/gsd-plan-phase {N}` (UI hint: yes), after `/design-shotgun` | `impeccable:critique` | Always when shotgun fires | UI-SPEC.md records impeccable score per variant + chosen variant ≥ quality bar |

### Phase execution gates

| GSD step | Required skill | Trigger | Evidence |
|---|---|---|---|
| Executor task with `tdd="true"` | `superpowers:test-driven-development` | Every TDD task | Two atomic commits: `test(RED): <desc>` then `feat(GREEN): <desc>`, with a third optional `refactor:` |
| Executor task creating/modifying frontend component | gstack `/browse` + screenshot | Every UI-touching task | Screenshot path referenced in commit message or SUMMARY.md |
| Executor claims a task is done | `superpowers:verification-before-completion` | Before every `TaskUpdate --completed` | Agent posts verification evidence (grep, test output, curl, screenshot) BEFORE marking done |
| Bug encountered mid-phase | `superpowers:systematic-debugging` | Any unexpected failure | Root-cause write-up in phase directory before any fix commit |
| `/gsd-debug` invoked | `superpowers:systematic-debugging` | Always | 4-phase protocol (Observe → Hypothesize → Test → Conclude) documented in debug session log |

### Post-phase gates

| GSD step | Required skill | Trigger | Evidence |
|---|---|---|---|
| After all executors complete | gstack `/review` (stage 1: spec compliance) | Always | REVIEW.md in phase directory |
| After `/review` passes | `superpowers:requesting-code-review` (stage 2: code quality) | Always | Independent reviewer agent output appended to REVIEW.md |
| Phase touches auth/storage/api/llm | gstack `/cso` | Scope match | SECURITY.md with ASVS-level threat coverage |
| Dev server reachable on localhost | gstack `/qa` | Scope match | QA report referenced in phase VERIFICATION.md |
| Before STATUS = Complete | `superpowers:verification-before-completion` | Always | VERIFICATION.md has 1:1 evidence for every must_have |
| Phase touches DB schema or RLS | `database-sentinel:audit` | Scope matches Supabase / Postgres / MongoDB | DB-AUDIT.md present; Critical / High findings resolved or recorded in ADR via `templates/adr-db-security-acceptance.md`; otherwise BLOCKS branch close |

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

### Programmatic hooks (5 hooks, v1.5.0+)

| Hook | Event | Matcher | What it enforces | Override |
|---|---|---|---|---|
| **1 Database Sentinel** | `PreToolUse` | `Bash\|Edit\|Write` | Blocks `DROP/TRUNCATE TABLE`, `DELETE` without `WHERE`, edits to `.env*`, edits to `migrations/*` without phase approval | `touch .planning/current-phase/migrations-approved` for migrations; ADR with explicit acceptance for SQL |
| **2 Design Shotgun Gate** | `PreToolUse` | `Edit\|Write` | Blocks edits to `*.tsx`/`*.css`/`design/`/`src/components/` without preflight sentinel | Run `/design-shotgun`; or `touch .planning/current-phase/design-shotgun-passed` for one-off (document override in commit) |
| **3 Phase Sentinel** | `Stop` | (none) | Haiku checks `.planning/current-phase/checklist.md` against the conversation; blocks `Stop` if items remain | Mark items complete or update the checklist before retry |
| **4 Skill Router Audit Log** | `PostToolUse` + `SessionStart` | `mcp__skills__.*\|Bash` | Logs every skill invocation as JSONL to `.planning/skill-observations/skill-router-{date}.jsonl`; surfaces last 20 on each new session | Informational only; no blocking |
| **5 Commitment Re-Injector** | `SessionStart` | `compact` | Re-injects `head -50 CLAUDE.md` + current-phase `COMMITMENT.md` after compaction | Informational only; no blocking. **GLOBAL** (cwd-aware, no-ops on non-AgenticApps projects) |

The 5 hooks split between two install locations:

- **Hooks 1-4** are project-scoped: live at `.claude/hooks/<name>.sh` and
  registered in the project's `.claude/settings.json`. Installed during
  `/setup-agenticapps-workflow` from `templates/.claude/hooks/` and the
  `templates/claude-settings.json` template.
- **Hook 5** is global: lives at `~/.claude/hooks/commitment-reinject.sh`
  and is registered in `~/.claude/settings.json` with `matcher: compact`.
  cwd-aware — no-ops on non-AgenticApps projects.

### Verifying hook installation

In any AgenticApps project, run:

```bash
~/.claude/skills/agenticapps-workflow/bin/check-hooks.sh
```

Reports `✓` for each hook present and registered; `✗` for anything missing.

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

## Config.json hooks — extended schema

The hooks block is extended from flag-based to skill-named. Orchestrator
code can read this when the enforcement layer becomes data-driven; until
then, the skill + CLAUDE.md layer reads it.

```json
{
  "hooks": {
    "pre_phase": {
      "brainstorm_ui": {
        "enabled": true,
        "skill": "superpowers:brainstorming",
        "trigger": "ui_hint_yes || frontend_files_in_scope",
        "evidence": "CONTEXT.md contains '## Design alternatives'"
      },
      "brainstorm_architecture": {
        "enabled": true,
        "skill": "superpowers:brainstorming",
        "trigger": "new_service || new_model || new_integration",
        "evidence": "RESEARCH.md contains 'Alternatives considered'"
      },
      "design_shotgun": {
        "enabled": true,
        "skill": "gstack:design-shotgun",
        "trigger": "ui_hint_yes && no_ui_spec_yet",
        "evidence": "UI-SPEC.md references variant paths"
      }
    },
    "per_plan": {
      "tdd_enforcement": {
        "enabled": true,
        "skill": "superpowers:test-driven-development",
        "trigger": "task.tdd == true",
        "evidence": "RED + GREEN commit pair per task"
      },
      "ui_preview": {
        "enabled": true,
        "skill": "gstack:browse",
        "trigger": "task modifies frontend components",
        "evidence": "screenshot referenced in commit or SUMMARY.md"
      },
      "verification_before_done": {
        "enabled": true,
        "skill": "superpowers:verification-before-completion",
        "trigger": "before any TaskUpdate --completed",
        "evidence": "verification output posted before status change"
      }
    },
    "post_phase": {
      "spec_review": {
        "enabled": true,
        "skill": "gstack:review",
        "trigger": "always",
        "evidence": "REVIEW.md in phase directory"
      },
      "code_quality_review": {
        "enabled": true,
        "skill": "superpowers:requesting-code-review",
        "trigger": "always, after spec_review",
        "evidence": "Stage 2 section in REVIEW.md"
      },
      "security": {
        "enabled": true,
        "skill": "gstack:cso",
        "trigger": "scope matches auth|storage|api|llm",
        "evidence": "SECURITY.md in phase directory"
      },
      "qa": {
        "enabled": true,
        "skill": "gstack:qa",
        "trigger": "dev server reachable on localhost",
        "evidence": "QA report linked from VERIFICATION.md"
      }
    },
    "finishing": {
      "branch_close": {
        "enabled": true,
        "skill": "superpowers:finishing-a-development-branch",
        "trigger": "feature branch ready to merge",
        "evidence": "PR description lists skills + gates + evidence links"
      }
    }
  }
}
```

## When to update this plan

- A pressure test fails in live development → add a new rationalization row
  AND update the failing scenario's "Correct response"
- A new Superpowers skill becomes available → add it to the gate mapping
- A GSD workflow step changes → update the gate-to-skill mapping
- A gstack command is renamed → update references

This document is code. Version it. Review changes in PRs. Never let it rot.
