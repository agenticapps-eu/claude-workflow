# CLAUDE.md Sections — paste into your project's CLAUDE.md

## Development Workflow

This project uses three complementary tools:

| Tool | Layer | Purpose |
|------|-------|---------|
| **Superpowers** | Discipline | Brainstorm → design → TDD → review cycle |
| **GSD** | Planning | Context-rot prevention, atomic tasks, phase tracking |
| **gstack** | Capability | QA, security scan, architecture review |

**Sequence:** Orient → Build → Verify → Record

1. Check GSD state → understand current task
2. Brainstorm with Superpowers (acceptance criteria, edge cases)
3. Implement with TDD discipline (red-green-refactor)
4. QA with `/qa`, security with `/cso`, review with `/review`
5. Update decision log if non-trivial decision was made
6. Update GSD state

See `.claude/skills/agentic-apps-workflow/SKILL.md` for full details.

### Superpowers Integration Hooks (MANDATORY — NON-NEGOTIABLE)

> **Enforcement contract:** `docs/workflow/ENFORCEMENT-PLAN.md`. Read it before
> any phase. The hooks below are commitments, not suggestions. Skipping a hook
> is a protocol violation.

**The flags in `.planning/config.json` → `hooks` declare intent but NO GSD
workflow code reads them.** Enforcement happens here, in CLAUDE.md, via the
commitment principle: when you activate the `agentic-apps-workflow` skill you
MUST emit the commitment ritual block (see ENFORCEMENT-PLAN.md §"The commitment
ritual") as your FIRST output text. Listing the skills commits you to them.

#### The Commitment Ritual (emit FIRST, before any tool call)

```
## Workflow commitment

I am using the agentic-apps-workflow skill for this task.
Task scope: {brief description}
Task size: {tiny | small | medium | large}

Skills I will invoke, in order:
1. {skill-name} — {why}
2. {skill-name} — {why}

Post-phase gates (if applicable): {review | cso | qa}
Verification evidence I will produce: {list}
```

#### Pre-Phase Hooks (before `/gsd-execute-phase`)

1. **Brainstorm UI plans + design critique** — For any plan with `UI hint: yes` in ROADMAP or
   frontend files in `files_modified`, you MUST invoke `superpowers:brainstorming`
   before planning. For phases generating new visual surfaces, you MUST ALSO
   run gstack `/design-shotgun` to generate 3–4 visual variants. **Then run
   `impeccable:critique` against each variant.** Variants scoring below the
   impeccable quality bar are eliminated before the user picks. Boot the dev
   server, preview via `/browse`, and get the user's explicit pick into
   UI-SPEC.md, with the impeccable score for the chosen variant recorded.
   No skipping this for "obvious" designs.

2. **Brainstorm architecture plans** — For plans introducing new services, data
   models, or integration patterns, you MUST invoke `superpowers:brainstorming`
   and record at least 2 alternatives in RESEARCH.md with rationale for the
   pick. "There's only one way" is a red flag — list alternatives anyway.

#### Per-Plan Hooks (during execution)

3. **TDD enforcement** — Tasks with `tdd="true"` MUST invoke
   `superpowers:test-driven-development`. Required artifact: two atomic commits
   per task — `test(RED): <desc>` then `feat(GREEN): <desc>`. If your
   executor produces a single commit with code + test together, DELETE IT AND
   START OVER. Non-negotiable.

4. **UI preview** — Plans modifying frontend components MUST start the dev
   server and verify rendering via `/browse` before committing. Screenshot
   path referenced in commit message or SUMMARY.md.

5. **Verification before completion** — Before any `TaskUpdate --completed`,
   you MUST invoke `superpowers:verification-before-completion` and post grep
   / test / curl / screenshot evidence. "It looks right" is not evidence.

#### Post-Phase Hooks (after executors complete, before verifier)

6. **Stage 1 — Spec review** — Always run gstack `/review` on the phase diff.
   Output: REVIEW.md.

7. **Stage 2 — Code quality review** — After `/review` passes, invoke
   `superpowers:requesting-code-review` for an independent code-quality pass.
   The reviewer agent is separate from the executor. Output: Stage 2 section
   appended to REVIEW.md. The two stages are NOT collapsible.

8. **Security scan** — Run gstack `/cso` when the phase touches auth, storage,
   API endpoints, or LLM prompt construction. Output: SECURITY.md.
   **Additionally,** when the phase touches Supabase / Postgres / MongoDB,
   you MUST also run `database-sentinel:audit`. Output: DB-AUDIT.md.
   Critical or High findings BLOCK branch close — they must be fixed
   (database-sentinel produces exact SQL DDL fixes) or accepted via ADR with
   user-explicit override using the template at
   `templates/adr-db-security-acceptance.md`.

9. **QA verification** — If a dev server is reachable (localhost:3000, :5173,
   or :8080), run gstack `/qa` on affected pages. Output referenced in
   VERIFICATION.md.

#### Finishing Hooks (feature branch ready to merge)

10. **Branch close** — Invoke `superpowers:finishing-a-development-branch` to
    compose the PR description. Must list: skills invoked, gates passed,
    verification evidence links.

#### Rationalization Table (pattern-match your own reasoning)

| If you think... | The reality is... |
|---|---|
| "Simple change, skip brainstorming" | Simple changes produce most outages. Brainstorming takes 2 min. |
| "TDD slows me down here" | TDD is faster than debugging silent regressions. |
| "I'll add tests after implementation" | Tests-after verify what was built, not what was needed. Sunk-cost trap. |
| "Existing tests cover this" | Prove it: run them, check coverage for modified lines. |
| "Manual testing is enough" | Not systematic, not repeatable, not in CI. Not verification. |
| "Design is obvious, skip brainstorming" | List ≥2 alternatives anyway. The "obvious" choice is suspect. |
| "/review is overkill for small PRs" | `/review` finds structural issues. Runs in 60s. Run it. |
| "User said skip tests because urgent" | Acknowledge urgency, explain risk, offer minimal critical-path tests. |
| "300 lines already written, adding tests wasteful" | Sunk cost. Delete-and-TDD or record `NO-TESTS-PER-USER-REQUEST` in commit. |
| "Workflow is overkill for this task" | Skill description says it triggers on ANY code change. Invoke it. |

#### 13 Red Flags — Trigger Automatic STOP → DELETE → RESTART

1. Code written before the test (for `tdd="true"` tasks)
2. Test added after implementation
3. Test passes on first run — no RED observed
4. Cannot explain why the test should have failed
5. Tests marked for "later" addition
6. Any "just this once" reasoning
7. Manual testing claimed as verification evidence
8. Two-stage review collapsed into one
9. Framing discipline as "ritual" or "ceremony"
10. Keeping pre-written code as "reference" while writing tests
11. Sunk-cost reasoning about deleting unverified code
12. Describing discipline as "dogmatic" or "slowing us down"
13. Any "This case is different because..." opener

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Design variants, visual brainstorm → invoke design-shotgun
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health
