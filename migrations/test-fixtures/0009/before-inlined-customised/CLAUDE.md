# Project — customised inlined block (mirrors cparx's heading shape)

This represents a project that had the workflow inlined and then edited
sections of it (e.g. team-specific commitment ritual phrasing). The
migration must detect the inlined block via the heading-level-agnostic
Superpowers regex and prompt the user about extracting it (because the
canonical content has diverged from team-edited content). **Heading
levels mirror the deprecated source — H3 for the Superpowers heading,
H4 for sub-hooks** — even after the team's customisations, because the
team only added rows to the table and an extra red-flag item; they
didn't restructure the heading hierarchy.

This fixture intentionally has NO smoking-gun H1 ("CLAUDE.md Sections —
paste...") because cparx's CLAUDE.md dropped that line during a manual
cleanup pass; only the H3 Superpowers marker remains as the detection
signal.

## Project overview

Project-specific content above the inlined block.

## Development Workflow

This project uses three complementary tools, **plus our team-specific
post-merge protocol** (see internal wiki).

| Tool | Layer | Purpose |
|------|-------|---------|
| **Superpowers** | Discipline | Brainstorm → design → TDD → review cycle |
| **GSD** | Planning | Context-rot prevention, atomic tasks, phase tracking |
| **gstack** | Capability | QA, security scan, architecture review |
| **TeamWiki** | Team-specific | (custom row added by this team) |

### Superpowers Integration Hooks (MANDATORY — NON-NEGOTIABLE)

(content elided in fixture — markers are what the migration grep-detects)

#### 13 Red Flags — Trigger Automatic STOP → DELETE → RESTART

1. Code written before the test (for `tdd="true"` tasks)
13. Any "This case is different because..." opener
14. **(team-added)** Skipping the post-merge protocol

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through
a GSD command. **(team-customised)** This team additionally requires Linear
issue ID in every commit subject.

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it.

Key routing rules:
- Bugs, errors → invoke investigate
- Ship, deploy, push → invoke ship
