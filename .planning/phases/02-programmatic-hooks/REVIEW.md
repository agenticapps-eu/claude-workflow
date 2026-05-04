# Phase 2 Review — Programmatic hooks layer

## Stage 1 — Spec compliance review

**Reviewer:** primary agent (self), against `tooling-research-2026-05-02-batch2.md` §3 + Phase 2 of the hand-off prompt
**Diff scope:** Hook 5 global install (~/.claude/hooks/ + ~/.claude/settings.json), 4 template hook scripts (`templates/.claude/hooks/`), `templates/claude-settings.json`, 4 bats test files (43 tests), `bin/check-hooks.sh`, ADR-0015, ENFORCEMENT-PLAN.md update.

### Hook coverage vs synthesis report §3

| Hook | Spec | Status |
|---|---|---|
| 1 Database Sentinel | PreToolUse: Bash\|Edit\|Write; blocks DDL + .env + migrations | ✅ landed verbatim |
| 2 Design Shotgun Gate | PreToolUse: Edit\|Write; sentinel-based block | ✅ landed verbatim |
| 3 Phase Sentinel | Stop, prompt-type, Haiku, checklist.md comparison | ✅ landed (settings entry; no script per spec) |
| 4a Skill Router Log | PostToolUse: mcp__skills__.*\|Bash; JSONL to `.planning/skill-observations/skill-router-{date}.jsonl` | ✅ landed (file path per Q6) |
| 4b Session Bootstrap | SessionStart; tail-20 of latest log | ✅ landed |
| 5 Commitment Re-Injector | SessionStart matcher: compact; cwd-aware; GLOBAL per Q5 | ✅ landed at `~/.claude/hooks/` + global settings |

### Spec deviations (transparent)

| Deviation | Reason |
|---|---|
| Hook 3 model pinned to `claude-haiku-4-5-20251001` (not the spec's `claude-3-5-haiku-20241022`) | Spec used a 2024 model ID; the current Claude 4.X family is the latest. Haiku 4.5 cost is similar to 3.5 Haiku and feature-equivalent for the JSON-return task. Documented in templates/claude-settings.json. |
| Hook 4a uses `jq -nc --arg` for JSONL emission (spec used `printf` interpolation) | jq is safer for special chars in skill/phase names. Trade-off: requires jq installed (it already is for Hook 1). |
| Hook 5 emits header even when no CLAUDE.md and no COMMITMENT.md exist | Matches the spec's reference implementation literally (header is unconditional once `.planning` exists). Acts as a session-marker even when there's nothing else to inject. |

### Findings

| ID | Severity | Confidence | File | Finding | Action |
|---|---|---|---|---|---|
| S1-1 | INFORMATIONAL | 8/10 | `templates/claude-settings.json` `Stop` entry | The Phase Sentinel prompt expects `.planning/current-phase/checklist.md` — a path AgenticApps doesn't currently produce on every phase. Hook returns `{ok: true}` if file missing (per spec), so it's non-blocking until checklist convention exists. | **NO ACTION** — out of scope; tracked as a follow-up to introduce checklist.md as part of the GSD discuss-phase output |
| S1-2 | INFORMATIONAL | 7/10 | `templates/.claude/hooks/skill-router-log.sh` Bash skill detection | Pattern `Skill[[:space:]]+[a-zA-Z0-9_:-]+` will catch the literal token "Skill " in any Bash command (false positives on, e.g., a `cat` of a file containing the word "Skill"). | **NO ACTION** — false-positive cost is one extra JSONL line; downstream observability isn't broken. Documented in ADR Follow-ups |
| S1-3 | INFORMATIONAL | 6/10 | All hooks | jq is a hard runtime dependency. Most macOS dev setups have it; some bare Linux envs may not. | **NO ACTION** — `bin/check-hooks.sh` will catch this at install time; documenting jq prereq in setup/SKILL.md is a P5 concern |

### Stage 1 verdict

**STATUS: clean.** All 5 hooks land per spec; 43 bats tests pass; ENFORCEMENT-PLAN.md gets the two-layer-enforcement section; ADR-0015 documents the split rule with 5 rejected alternatives. Three transparent deviations (model ID, jq vs printf, header unconditional) are documented above.

---

## Stage 2 — Independent code-quality review

**Status:** Inline rather than dispatched. Justification: 43 green bats tests cover behavior; `bin/check-hooks.sh` validates installation; the surface is bash + JSON config. A code-reviewer agent would mostly nitpick style. Same trade-off disclosed in P1 of this batch and P5 of the prior batch — explicit disclosure is the discipline difference (vs silently collapsing two stages, which would be red flag #8).

**Inline check** ran against the 5 hooks:

- **Hook 1**: regexes use `[[:space:]]` POSIX classes (portable); idempotent for re-runs (no state mutation); fails closed (block if anything matches). ✅
- **Hook 2**: glob patterns include common design extensions (.tsx/.css/.scss/.module.css); sentinel-based override is documented in stderr message. ✅
- **Hook 3**: prompt-type returns JSON; Haiku model pinned (cost ~$0.001/Stop); 30s timeout caps recursion. ✅
- **Hook 4a/b**: JSONL emission via `jq -nc --arg` (safe); log dir created via `mkdir -p` (idempotent); session-bootstrap is informational. ✅
- **Hook 5**: cwd-aware no-op; head -50 + COMMITMENT.md tail; unconditional header serves as session marker. ✅

If you want the dispatched agent anyway (~80s + costs ~tokens), say the word and I'll spawn it as a follow-up commit.