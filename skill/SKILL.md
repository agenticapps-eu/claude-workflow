---
name: agentic-apps-workflow
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

# AgenticApps Development Workflow

This workflow applies to all AgenticApps projects. It uses three complementary
tools — Superpowers, GSD, and gstack — to enforce spec-first discipline without
slowing you down.

## Why This Exists

Two failure modes kill solo projects:
1. **Diving into code without thinking** — leads to rework, wasted hours, untraceable decisions
2. **Over-planning without shipping** — burns budget on process instead of output

The balance: think just enough to be confident, then move fast with guardrails.

## Project Configuration

Before using this workflow, check if a `.claude/workflow-config.md` file exists
in the project root. If it does, read it for project-specific settings
(environment strategy, Linear project, repo conventions, client requirements).
If it doesn't exist, suggest running `/setup-gstack-gsd-superpowers-workflow`
to configure the project.

## The Three Tools

| Tool | Layer | When to invoke | What it prevents |
|------|-------|---------------|-----------------|
| **Superpowers** | Discipline | Before writing any code | Cowboy coding, missing edge cases, untested code |
| **GSD** | Planning | At session start and when switching tasks | Context rot, lost progress, scope creep |
| **gstack** | Capability | After implementation, before commit | QA gaps, security blind spots, architecture drift |

They don't overlap — Superpowers governs *how* to code (TDD, design-first),
GSD governs *what to code next* (planning, context preservation), and gstack
provides *cross-cutting checks* (QA, security, architecture review).

## Mandatory Workflow Sequence

Every task follows this sequence. Each step should be proportional to the task
size — a 15-minute fix gets lighter treatment than a new feature.

### Phase 1: Orient (before touching code)

**Step 1 — Check GSD state**
Read the current GSD planning files to understand where you are.
What wave are you in? What's the current task? Is there leftover context?

If this is a new session or a new task:
- Run the GSD planning flow to break the work into 2-3 atomic tasks
- Each task should be completable in a single focused session
- Write the plan to GSD planning files so it survives context loss
**Step 2 — Brainstorm with Superpowers**
Before writing implementation code, use Superpowers to:
- Clarify what "done" looks like (acceptance criteria)
- Identify edge cases and failure modes
- Produce a short design doc (even 3-5 bullet points counts)

The design doc becomes part of the decision log — the traceable spec-first
artefact that justifies every choice.

### Phase 2: Build (write the code)

**Step 3 — Implement with TDD discipline**
Superpowers enforces red-green-refactor:
1. Write a failing test that captures the acceptance criteria
2. Write the minimum code to make it pass
3. Refactor for clarity
4. Repeat

For frontend/UI work where TDD is impractical, write the component first,
then add a smoke test or visual check.

Keep commits atomic — one logical change per commit. Reference the Linear
issue in the commit message (e.g., `AGE-17: document ingestion OCR stub`).

### Phase 3: Verify (before committing)

**Step 4 — QA with gstack**
Run `/qa` to verify the implementation works in a real environment.
For backend: API smoke tests. For frontend: real browser verification.
**Step 5 — Security scan with gstack**
Run `/cso` for an OWASP-style security check. Especially important for:
- Auth or RLS changes
- File upload / document handling
- API endpoints exposed to users
- LLM prompt construction (injection risks)

**Step 6 — Architecture review with gstack**
Run `/review` for a staff-engineer-level code review.
Does this fit the architecture spec? Does it match the data model?
Are there unnecessary dependencies?

### Phase 4: Record (after committing)

**Step 7 — Update the decision log**
If this task involved a non-trivial decision (technology choice, architecture
trade-off, algorithm design, UX direction), add an entry:

```
docs/decisions/NNNN-short-title.md
```

Format:
```markdown
# ADR-NNNN: [Title]
**Status**: Accepted
**Date**: [YYYY-MM-DD]
**Linear**: [ISSUE-ID]

## Context
[Why did this decision come up?]
## Decision
[What we chose and the key reasons]

## Alternatives Rejected
[What we didn't choose and why]

## Consequences
[What this means for future work]
```

**Step 8 — Update Linear**
Move the issue to the appropriate state. Add a comment summarising what was
done if it's not obvious from the commit message.

**Step 9 — Update GSD state**
Mark the current task complete in the GSD planning files.
If the next task is ready, note it. If the wave is complete, plan the next wave.

## Scaling to Task Size

| Task size | Example | Workflow |
|-----------|---------|----------|
| **Tiny** (< 15 min) | Fix a typo, update config | Skip brainstorm → implement → commit → update Linear |
| **Small** (15-60 min) | Add a field, fix a bug | 3-bullet brainstorm → implement with test → `/review` → commit |
| **Medium** (1-4 hours) | New endpoint, new component | Full workflow, lightweight ADR |
| **Large** (4+ hours) | New subsystem, major feature | Full workflow, detailed ADR, break into GSD sub-tasks |

## Quick Reference: Daily Start

1. Check GSD state — where did I leave off?
2. Check Linear — what's the highest-priority unblocked issue?
3. Pull latest from the development branch
4. Pick the task, follow the workflow above
5. At end of session: update GSD state, push branch, update Linear