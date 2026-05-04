# Phase 3 Verification — Mattpocock skills install

**Phase:** 03-mattpocock-install
**Spec source:** Hand-off prompt Phase 3 + synthesis report §1
**Date:** 2026-05-03

## Install (this session)

### MH-1: `improve-codebase-architecture` installed globally

- **Evidence:** `ls ~/.claude/skills/mattpocock-improve-architecture/SKILL.md` → 5.1KB; cloned from `mattpocock/skills/skills/engineering/improve-codebase-architecture/`. SKILL.md frontmatter `name: improve-codebase-architecture`, description matches the spec.
- **Status:** ✅ PASS

### MH-2: `grill-with-docs` installed globally

- **Evidence:** `ls ~/.claude/skills/mattpocock-grill-with-docs/SKILL.md` → 3.6KB; cloned from `mattpocock/skills/skills/engineering/grill-with-docs/`. Soft prerequisite for the audit skill (writes CONTEXT.md).
- **Status:** ✅ PASS

### MH-3: ADR-0016 written

- **Evidence:** `docs/decisions/0016-mattpocock-architecture-audit.md` documents the install decision, four rejected alternatives, vocabulary collision risk, "Linear backlog only, never auto-apply" rule.
- **Status:** ✅ PASS

## Deferred follow-ups (user-driven, post-merge)

The user chose **Q3 option C** ("Install + CONTEXT.md + run first audit, file findings in Linear backlog") which has agent-uninstallable parts:

### Follow-up A: Interactive `/grill-with-docs` against cparx

- **What:** ~15-30 min interactive session in cparx where the user answers domain questions (entities, invariants, key flows). Output: `~/Sourcecode/cparx/CONTEXT.md`. Reusable artifact for any future skill needing domain glossary.
- **Why deferred:** the skill is interactive (it asks the user questions one at a time). An agent can't drive its own answer turn.
- **How to do:** `cd ~/Sourcecode/cparx && claude` → in the session: "/grill-with-docs" → answer the questions.

### Follow-up B: First architecture audit on cparx

- **What:** Run `/improve-codebase-architecture` in cparx after CONTEXT.md exists. Output: numbered candidates at `~/Sourcecode/cparx/.planning/audits/2026-XX-XX-architecture.md`.
- **Why deferred:** depends on Follow-up A.
- **How to do:** `cd ~/Sourcecode/cparx && claude` → in the session: "/improve-codebase-architecture" → triage the output.

### Follow-up C: Triage findings into Linear backlog

- **What:** For each accepted refactor candidate, file a Linear issue (manual or via Linear MCP). Reject candidates that conflict with documented ADRs.
- **Why deferred:** depends on Follow-up B.
- **How to do:** review the audit markdown; for each Files / Problem / Solution / Benefits block, decide accept/reject; file accepted ones as Linear issues with the audit citation.

## Why this scope split

The original Q3 answer (option C) reads as "make all artifacts ready so when I sit down post-cparx-demo, I can do this frictionlessly." The install part of that scope IS done in this session. The interactive parts are flagged in:
- `session-handoff.md` (next-session pickup)
- The PR body (so reviewers see the deferred actions)
- This VERIFICATION.md (auditable record)

Not skipping; deferring with explicit handoff.

## Skills invoked this phase

1. `superpowers:writing-plans` — phase plan held inline (small phase, 2 git clones + ADR)
2. gstack `/review` — Stage 1 self-review (small surface; mostly upstream content cloned verbatim)
3. `pr-review-toolkit:code-reviewer` — Stage 2 inline (no AgenticApps-authored code in this phase; just installs of upstream content)
