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

### Superpowers Integration Hooks (MANDATORY)

These hooks are enforced during GSD phase execution. Config: `.planning/config.json` → `hooks`.

#### Pre-Phase Hooks (before `/gsd-execute-phase`)
Run these BEFORE spawning executor agents:

1. **Brainstorm UI plans** (`hooks.pre_phase.brainstorm_ui`): For any plan with `UI hint: yes` in the ROADMAP or frontend files in `files_modified`, invoke `superpowers:brainstorming` to explore UI/UX alternatives. Start the dev server and use `/browse` to preview component variants. The user picks the direction before execution begins.

2. **Brainstorm architecture plans** (`hooks.pre_phase.brainstorm_architecture`): For plans introducing new services, data models, or integration patterns, invoke `superpowers:brainstorming` to identify edge cases, acceptance criteria, and design alternatives before implementation.

#### Per-Plan Hooks (during execution)
These rules apply to every executor agent:

3. **TDD enforcement** (`hooks.per_plan.tdd_enforcement`): For tasks marked `tdd="true"` in the plan, the executor MUST write the failing test FIRST, verify it fails, then write the implementation, then verify it passes. Do not write implementation and tests together. Red-green-refactor, strictly.

4. **UI preview** (`hooks.per_plan.ui_preview`): For plans that create or modify frontend components, the executor must start the dev server and verify the component renders correctly using `/browse` before committing. Screenshot evidence required.

#### Post-Phase Hooks (after all plans complete, before phase verification)
Run these AFTER all executor agents complete, BEFORE the verifier:

5. **Code review** (`hooks.post_phase.review`): Always run `/review` on the phase diff. This is the pre-landing review that catches structural issues tests miss.

6. **Security scan** (`hooks.post_phase.cso`): Run `/cso` when the phase touches auth, storage, API endpoints, or LLM prompt construction. Skip for pure UI or documentation phases.

7. **QA verification** (`hooks.post_phase.qa`): If a dev server is reachable (localhost:3000, :5173, or :8080), run `/qa` on affected pages. Skip if no server is running.

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
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
- Save progress, checkpoint, resume → invoke checkpoint
- Code quality, health check → invoke health
