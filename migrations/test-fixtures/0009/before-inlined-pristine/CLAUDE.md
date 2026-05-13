# Project — pristine inlined block (mirrors fx-signal-agent's actual shape)

This represents the fx-signal-agent shape: consumer project ran
`/setup-agenticapps-workflow` at some point and had the deprecated
`templates/claude-md-sections.md` template `cat`-ed into CLAUDE.md
verbatim. The H1 line below is the smoking gun. **Heading levels match
the deprecated source byte-for-byte: H3 for "Superpowers Integration
Hooks", H4 for sub-hooks.**

## Project overview

A line of project-specific content above the inlined block.

# CLAUDE.md Sections — paste into your project's CLAUDE.md

## Development Workflow

This project uses three complementary tools:

| Tool | Layer | Purpose |
|------|-------|---------|
| **Superpowers** | Discipline | Brainstorm → design → TDD → review cycle |
| **GSD** | Planning | Context-rot prevention, atomic tasks, phase tracking |
| **gstack** | Capability | QA, security scan, architecture review |

### Superpowers Integration Hooks (MANDATORY — NON-NEGOTIABLE)

(content elided in fixture — markers are what the migration grep-detects)

#### 13 Red Flags — Trigger Automatic STOP → DELETE → RESTART

1. Code written before the test (for `tdd="true"` tasks)
13. Any "This case is different because..." opener

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through
a GSD command so planning artifacts and execution context stay in sync.

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it.

Key routing rules:
- Bugs, errors → invoke investigate
- Ship, deploy, push → invoke ship
