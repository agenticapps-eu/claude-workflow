---
name: agentic-apps-workflow
version: 1.12.0
implements_spec: 0.3.0
description: |
  Enforces the spec-first development workflow using Superpowers + GSD + gstack
  for any AgenticApps project. This skill MUST activate whenever Claude is asked
  to implement, build, code, fix, refactor, or design anything in the current
  project — regardless of whether the user explicitly mentions the workflow.
  Triggers on: "let's work on [issue]", "implement the [feature]", "build the
  [component]", "fix the [bug]", any task involving writing or changing code,
  creating architecture, or making technical decisions. The skill ensures every
  piece of work follows the Superpowers + GSD + gstack discipline and produces
  traceable decision artefacts. Use this even when the user just says "start
  working" or references a Linear issue number.
---

# AgenticApps Development Workflow — Enforcement Skill

**This is an enforcement skill, not documentation.** Its job is to make you
commit — publicly and in writing — to invoking the right Superpowers, GSD, and
gstack skills in the right order. Once committed, the commitment principle
(Cialdini; Wharton GAIL 2025) keeps you consistent with what you said you'd do.

**Authoritative contract:** `docs/workflow/ENFORCEMENT-PLAN.md`. Read it if you
are unsure which skill gates which step.

## Step 0 — The Commitment Ritual (NON-NEGOTIABLE)

As the FIRST user-facing output of your turn, before any tool call or
clarifying question, you MUST emit a `## Workflow commitment` block:

```
## Workflow commitment

I am using the agentic-apps-workflow skill for this task.
Task scope: {one-sentence description}
Task size: {tiny | small | medium | large}

Skills I will invoke, in order:
1. {skill-name} — {why it applies}
2. {skill-name} — {why it applies}
...

Post-phase gates (if applicable): {review | cso | qa}
Verification evidence I will produce: {list of artifacts}

Once I have stated this plan, I am committed to it. Deviating without
explicit user approval is a protocol violation.
```

Skipping this ritual is itself a protocol violation. You cannot rationalize
your way out of it — see the rationalization table below.

## Step 1 — Pick the task size, match the skill set

| Task size | Examples | Required skill invocations |
|---|---|---|
| **Tiny** (< 15 min) | Typo, config tweak, one-line fix | `superpowers:verification-before-completion` + commit |
| **Small** (15–60 min) | Single field, small bug | `superpowers:brainstorming` (3 bullets) → fix → `/review` → verification → commit |
| **Medium** (1–4 hours) | New endpoint, new component | Full workflow, lightweight ADR |
| **Large** (4+ hours) | New subsystem, major feature | Full workflow + detailed ADR + GSD phase plan |

## Step 2 — Route to the right GSD entry point

| Entry point | When |
|---|---|
| `/gsd-quick` | Tiny or small tasks; ad-hoc work |
| `/gsd-debug` | Investigation, bug fixing — auto-invokes `superpowers:systematic-debugging` |
| `/gsd-discuss-phase {N}` | New phase, CONTEXT.md missing, UX/architecture decisions pending |
| `/gsd-plan-phase {N}` | CONTEXT.md exists, ready to plan |
| `/gsd-execute-phase {N}` | Plans approved, ready to execute |

If you are about to Edit / Write / or run git commands without going through a
GSD entry point, **stop**. Either invoke one, or state in one sentence why
this task is genuinely out-of-scope for GSD.

## Step 3 — Invoke the Superpowers skills mapped to each GSD gate

This is the gate-to-skill map. Every row is a commitment.

### Planning gates

- `/gsd-discuss-phase {N}` → `superpowers:brainstorming` BEFORE the first
  discuss question. The design alternatives surfaced become the input to
  CONTEXT.md.
- `/gsd-plan-phase {N}` with `UI hint: yes` → gstack `/design-shotgun`
  (generate 3–4 visual variants, boot dev server, preview via `/browse`) +
  `/gsd-ui-phase {N}` to lock UI-SPEC.md.
- `/gsd-plan-phase {N}` for new service / model / integration →
  `superpowers:brainstorming` (record ≥2 alternatives in RESEARCH.md).
- `/gsd-plan-phase {N}` always → `superpowers:writing-plans`.

### Execution gates

- Task with `tdd="true"` → `superpowers:test-driven-development`. Required
  evidence: atomic `test(RED): <desc>` commit followed by
  `feat(GREEN): <desc>` commit. Optional `refactor:` commit.
- Task modifying frontend component → boot Vite dev server + `/browse`
  screenshot, referenced in commit message or SUMMARY.md.
- Before every `TaskUpdate --completed` →
  `superpowers:verification-before-completion`. Post grep / test / curl /
  screenshot evidence.
- Mid-phase bug → `superpowers:systematic-debugging`. 4-phase protocol:
  Observe → Hypothesize → Test → Conclude.

### Post-phase gates

- gstack `/review` (stage 1: spec compliance) → REVIEW.md.
- `superpowers:requesting-code-review` (stage 2: code quality, independent
  reviewer) → Stage 2 section in REVIEW.md. DO NOT collapse the two stages
  into one review.
- Phase touches auth / storage / api / llm → gstack `/cso` → SECURITY.md.
- Dev server reachable → gstack `/qa` → report linked from VERIFICATION.md.
- VERIFICATION.md must have 1:1 evidence per must_have.

### Finishing gate

- Feature branch ready to merge → `superpowers:finishing-a-development-branch`
  to compose the PR description.

## Step 4 — Record the decision

Non-trivial decisions (technology choice, architecture trade-off, algorithm
design, UX direction) get an ADR at `docs/decisions/NNNN-short-title.md`:

```
# ADR-NNNN: [Title]
**Status**: Accepted  **Date**: [YYYY-MM-DD]  **Linear**: [ISSUE-ID]

## Context
[Why did this decision come up?]

## Decision
[What we chose and the key reasons]

## Alternatives Rejected
[What we didn't choose and why]

## Consequences
[What this means for future work]
```

## Rationalization Table — Check Before Skipping Anything

| If you think... | The reality is... |
|---|---|
| "This task is too small for the commitment ritual" | The ritual takes 15 seconds. Skipping it is how discipline erodes. Emit the block. |
| "Skill is obvious, no need to announce it" | The announcement IS the commitment. Announcement → consistency pressure → compliance. |
| "TDD is impractical for frontend" | Snapshot tests, `/browse` screenshot diffs, visual regression count as TDD. Write the test first. |
| "I've already thought about alternatives" | If you didn't write them down, you didn't consider them. List ≥2 in RESEARCH.md. |
| "`/gsd-review` is excessive — just one model's plan is fine" | Different LLMs catch different blind spots. A plan that survives review from 2–3 independent reviewers is more robust. Run it. (cparx phases 04.9 → 05 silently dropped this for 8 phases — that's the failure mode ADR 0018 closes.) |
| "Two-stage review is excessive" | Stage 1 catches spec drift, Stage 2 catches code-quality drift. Different failures, different agents. |
| "Dev server isn't worth booting for this change" | If you touched JSX/TSX, boot it. 30 seconds. |
| "The user explicitly said ship fast" | Acknowledge urgency, explain risk in one sentence, offer minimum discipline that protects the critical path. |

## 14 Red Flags — STOP → DELETE → RESTART

1. Code written before the test (for TDD tasks)
2. Test added after implementation
3. Test passes on first run — no RED observed
4. Cannot explain why the test should have failed
5. Tests marked for "later" addition
6. "Just this once" reasoning
7. Manual testing claimed as verification evidence
8. `/gsd-review` skipped — no `{phase}-REVIEWS.md` artifact
9. Two-stage review collapsed into one
10. Framing discipline as "ritual" or "ceremony"
11. Keeping pre-written code as "reference" while writing tests
12. Sunk-cost reasoning about deleting unverified code
13. Describing discipline as "dogmatic"
14. "This case is different because..."

## Pressure-Test Scenarios — Self-Check

Before you skip any step, ask yourself:
- Would I skip this step if this code were running in production serving real users?
- Would a senior engineer reviewing this work accept the shortcut?
- Am I rationalizing? Check the rationalization table above.

If any answer gives you pause, follow the protocol.

## Verification Check (after phase completes)

Run this to prove the workflow actually fired:

```bash
# Commitment block present
grep -rn "## Workflow commitment" .planning/phases/{padded_phase}-*/ 2>/dev/null

# TDD tasks produced RED + GREEN commits
git log --oneline {phase_base}..HEAD | grep -cE "^[a-f0-9]+ (test|feat)\("

# Multi-AI plan review evidence (pre-execution)
test -f .planning/phases/{padded_phase}-*/{padded_phase}-REVIEWS.md \
  && wc -l .planning/phases/{padded_phase}-*/{padded_phase}-REVIEWS.md

# Two-stage review evidence (post-execution)
grep -l "Stage 2" .planning/phases/{padded_phase}-*/REVIEW.md

# Evidence per must_have in VERIFICATION.md
grep -c "^- \*\*Evidence" .planning/phases/{padded_phase}-*/VERIFICATION.md
```

If any check fails, the phase did NOT honor the enforcement plan. File this as
a process bug, update `docs/workflow/ENFORCEMENT-PLAN.md` to close the
loophole, and re-run the failed gate.

## Daily Quick Reference

1. Check GSD state — where did I leave off?
2. Check Linear — highest-priority unblocked issue?
3. Pull latest from base branch
4. Pick the task, emit the commitment ritual
5. Route to the right GSD entry point
6. Invoke the mapped Superpowers skills in order
7. Update decision log + GSD state at end of session
