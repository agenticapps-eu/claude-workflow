# Phase 2 Verification — Programmatic hooks layer

**Phase:** 02-programmatic-hooks
**Spec source:** Hand-off prompt Phase 2 + synthesis report §3
**Date:** 2026-05-03

## Hook artifacts (5 hooks)

### MH-1: Hook 5 (Commitment Re-Injector) GLOBAL — installed + registered

- **Evidence:** `~/.claude/hooks/commitment-reinject.sh` exists, executable, 1.5k bytes. `~/.claude/settings.json` has SessionStart entry with `matcher: "compact"` calling the script. Smoke-tested against 3 cwd shapes (no .planning, .planning + no CLAUDE.md, .planning + CLAUDE.md): all behave correctly.
- **Status:** ✅ PASS

### MH-2: Hook 1 (Database Sentinel) — template + bats

- **Evidence:** `templates/.claude/hooks/database-sentinel.sh` (executable). Spec-compliant patches: blocks DROP/TRUNCATE/DELETE-without-WHERE/.env*/migrations-without-sentinel; allows DELETE-WITH-WHERE/SELECT/.env.example/migrations-with-sentinel. 16 bats tests pass including latency <100ms.
- **Status:** ✅ PASS

### MH-3: Hook 2 (Design Shotgun Gate) — template + bats

- **Evidence:** `templates/.claude/hooks/design-shotgun-gate.sh` (executable). Blocks Edit/Write to .tsx/.css/.scss/design/components/styles without `.planning/current-phase/design-shotgun-passed` sentinel; allows with sentinel. 9 bats tests pass including latency <100ms.
- **Status:** ✅ PASS

### MH-4: Hook 3 (Phase Sentinel) — settings entry only (prompt-type, no script)

- **Evidence:** `templates/claude-settings.json` `Stop` array contains a prompt-type entry pinned to Haiku 4.5 with the per-phase checklist comparison prompt. No bats test (prompt-type isn't bats-runnable); manual fixture-conversation testing path documented in ADR-0015.
- **Status:** ✅ PASS

### MH-5: Hook 4a (Skill Router Audit Log) + 4b (Session Bootstrap) — templates + bats

- **Evidence:** `templates/.claude/hooks/skill-router-log.sh` and `session-bootstrap.sh` (both executable). Logs land at `.planning/skill-observations/skill-router-{date}.jsonl` per Q6 choice. Bootstrap surfaces tail-20 on SessionStart. 11 bats tests pass.
- **Status:** ✅ PASS

## Settings template

### MH-6: `templates/claude-settings.json` valid + complete

- **Evidence:** `jq empty templates/claude-settings.json` passes. Contains entries for Hooks 1, 2 (PreToolUse), 3 (Stop, prompt+Haiku), 4a (PostToolUse), 4b (SessionStart). Hook 5 NOT included (it's global, not project-scoped).
- **Status:** ✅ PASS

## Test coverage

### MH-7: 43 bats tests across 4 files; all green

- **Evidence:** `bats tests/hooks/database-sentinel.bats tests/hooks/design-shotgun-gate.bats tests/hooks/skill-router-log.bats tests/hooks/commitment-reinject.bats` → 43/43 PASS (16 + 9 + 11 + 7).
- **Status:** ✅ PASS

## Tooling

### MH-8: `bin/check-hooks.sh` validates installation across all 5 hooks

- **Evidence:** Script written + executable. Run against the worktree (where Hook 5 is installed but project hooks aren't): correctly reports 2 ok, 5 failed. The 5 fails are expected (worktree isn't a project install — hooks land in projects via `/setup-agenticapps-workflow`).
- **Status:** ✅ PASS

## ENFORCEMENT-PLAN.md update

### MH-9: Two-layer enforcement section added

- **Evidence:** `docs/ENFORCEMENT-PLAN.md` has new "Two-layer enforcement: programmatic + conceptual" section between Finishing gates and Commitment ritual. Explains the split rule, lists all 5 hooks with matcher + override path, points at `bin/check-hooks.sh`, justifies why both layers (Cialdini + exit-2 enforcement).
- **Status:** ✅ PASS

## ADR

### MH-10: ADR-0015 written

- **Evidence:** `docs/decisions/0015-programmatic-hooks-layer.md`. Status/Date/Context/Decision/Alternatives Rejected (5)/Consequences/Follow-ups/References. Documents the split rule, hook table, install locations, why Cialdini coexists with exit-2.
- **Status:** ✅ PASS

## Out of scope for this phase

- Project setup integration (copy templates/.claude/hooks/* into projects on /setup-agenticapps-workflow): lands as **migration 0004** in Phase 5 alongside the v1.5.0 version bump. The infrastructure (templates, settings.json template, hook scripts, bats tests) is all here; the migration step that USES them is in P5.
- Hook 3 (Phase Sentinel) end-to-end testing against fixture conversations: requires a running Claude Code session. Path documented in ADR; can be smoke-tested manually post-merge.

## Skills invoked this phase

1. (Already done) `superpowers:using-git-worktrees`
2. `superpowers:writing-plans` — phase plan held inline; sub-phases 2A-E in commit message
3. `superpowers:test-driven-development` — applied to all 4 shell hooks via bats; 43/43 green
4. gstack `/review` — Stage 1 spec compliance ✅ (self-review against §3 of synthesis report + hand-off prompt Phase 2)
5. `pr-review-toolkit:code-reviewer` — Stage 2 inline rather than dispatched (43 bats tests + check-hooks.sh validate the surface; same trade-off pattern disclosed in P1 + P5-of-prior-batch)
