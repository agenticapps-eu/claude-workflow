# ADR-0015: Programmatic hooks layer (5 hooks across PreToolUse / PostToolUse / Stop / SessionStart)

**Status:** Accepted
**Date:** 2026-05-03
**Linear:** —
**Phase:** Phase 2 of `feat/programmatic-hooks-architecture-audit`

## Context

The AgenticApps workflow's enforcement contract — the commitment ritual, the
13 red flags, the rationalization table, the gate-to-skill mapping — lives
exclusively in CLAUDE.md prose. This works while the session is fresh, but
**fails silently on compaction and cold-start**: the prose degrades to
context-rot and the discipline disappears without explicit failure.

Vikas Sah and Ketan Damle (synthesis report §3) make the same critique:

> "Exit code 2 is the most important number in Claude Code. It's the only
> way to truly block an action." (Sah)
>
> "Without hooks, you're always checking Claude's work after the fact.
> With hooks, those questions go away." (Damle)

Claude Code's hook system fires shell scripts (or prompt-type sub-agents) on
4 event classes: `PreToolUse`, `PostToolUse`, `Stop`, `SessionStart`. Exit
code 2 from a hook BLOCKS the triggering action and routes stderr back to
Claude as feedback. This is the deterministic enforcement the prose layer
lacks.

## Decision

Add **5 programmatic hooks** as a complementary layer on top of the
existing CLAUDE.md prose discipline. Keep both layers — programmatic for
gates that must never be overridden; prose for skill routing and intent.

### The split rule

| Layer | What it enforces | How | Failure mode |
|---|---|---|---|
| **Conceptual** (existing) | Which skill should fire when, how phases sequence | CLAUDE.md prose + Cialdini commitment | Compaction / cold session = context-rot |
| **Programmatic** (new) | Tool-level deterministic gates | `PreToolUse` / `PostToolUse` / `Stop` / `SessionStart` shell scripts with `exit 2` | Slow shell hooks add latency |

If a violation costs you a phase iteration → programmatic hook.
If it's a routing/intent question → prose.

### The 5 hooks

| Hook | Type | Event | Matcher | What it does |
|---|---|---|---|---|
| **Hook 1 — Database Sentinel** | command | `PreToolUse` | `Bash\|Edit\|Write` | Blocks `DROP/TRUNCATE TABLE`, `DELETE FROM` without `WHERE`, edits to `.env*` and `migrations/*` (without phase approval). Exit 2. |
| **Hook 2 — Design Shotgun Gate** | command | `PreToolUse` | `Edit\|Write` | Blocks edits to `*.tsx`/`*.css`/`design/`/`src/components/`/`src/styles/` unless `.planning/current-phase/design-shotgun-passed` exists. Exit 2. |
| **Hook 3 — Phase Sentinel** | prompt (Haiku) | `Stop` | (none) | Compares `.planning/current-phase/checklist.md` against the conversation; returns `{ok: false, reason: ...}` if items remain unchecked. Exit 2 → blocks Stop. |
| **Hook 4a — Skill Router Log** | command | `PostToolUse` | `mcp__skills__.*\|Bash` | Appends `{ts, skill, phase, tool}` JSONL to `.planning/skill-observations/skill-router-{date}.jsonl`. Always exit 0 (logging, not blocking). |
| **Hook 4b — Session Bootstrap** | command | `SessionStart` | (none) | Outputs `tail -20` of latest skill-router log so each new session sees what fired last session. Always exit 0. |
| **Hook 5 — Commitment Re-Injector** | command | `SessionStart` | `compact` | After compaction strips context, re-injects `head -50 CLAUDE.md` + current-phase `COMMITMENT.md` if present. cwd-aware: no-ops on non-AgenticApps projects. **GLOBAL** at `~/.claude/hooks/`. |

### Where hooks live

- **Hooks 1-4 (project-scoped):** `templates/.claude/hooks/*.sh` in the
  scaffolder; copied into each project's `.claude/hooks/` by
  `/setup-agenticapps-workflow`. Project's `.claude/settings.json` registers
  them. This is per-project so each repo can customize the regex anchors.
- **Hook 5 (global):** `~/.claude/hooks/commitment-reinject.sh` registered
  in `~/.claude/settings.json` with `matcher: compact`. Per Q5 (user-confirmed):
  cwd-aware, no-ops on non-AgenticApps projects. One install, works for every
  AgenticApps project automatically.

### TDD and bats

Every shell hook ships with a bats test file (`tests/hooks/<hook>.bats`).
Test cases per hook spec in synthesis report §3. Total: 43 tests across
4 files (Hook 3 is prompt-type and tested via fixture conversations,
documented in setup/SKILL.md but not bats-runnable).

## Alternatives Rejected

- **Promote all conceptual hooks to programmatic.** Rejected — would dissolve
  the Cialdini commitment effect. The prose layer is a feature: stating a
  commitment binds future-you in a way exit codes can't. Keep both.
- **Use `exit 1` instead of `exit 2`.** Rejected — `exit 1` only logs; `exit 2`
  truly blocks. Sah's verbatim warning was the trigger: *"If you build security
  hooks and forget the distinction, you have logging, not enforcement."*
- **Inline everything in `~/.claude/settings.json` instead of separate scripts.**
  Rejected — settings hooks support only single-line `command:` strings; complex
  logic (regex, jq, conditional sentinels) fits in real script files. Plus
  scripts are testable with bats; inline strings aren't.
- **Make Hook 5 (Commitment Re-Injector) project-scoped like the others.**
  Rejected per Q5 — global with cwd-awareness is one-install for all projects;
  per-project would force every repo to register its own settings. Cost
  (one global script that no-ops gracefully) is much lower than benefit
  (zero-friction discipline-survival across all AgenticApps work).
- **Run the Phase Sentinel (Hook 3) on Sonnet/Opus instead of Haiku.**
  Rejected per synthesis warning: prompt-type Stop hooks fire on every
  Claude turn; pinning to Haiku keeps cost negligible (~$0.001/Stop).

## Consequences

**Positive:**
- Discipline survives compaction (Hook 5 re-injects the commitment).
- Database security violations and migration edits without phase approval
  cannot ship by accident — exit 2 blocks at the tool boundary.
- Design surface edits without preflight cannot ship — composes cleanly with
  the future `agenticapps-design-preflight` skill (skill writes the sentinel;
  this hook enforces its presence).
- Every skill invocation is logged to `.planning/skill-observations/` for
  observability + dashboard consumption.
- Premature `Stop` (Claude says "done" before phase complete) is caught by
  Hook 3 with Haiku-cheap inference.
- Bats coverage means hook regressions are caught at PR time, not in production.

**Negative:**
- Sub-100ms latency budget per `PreToolUse` invocation; complex regex or
  network calls in hooks would compound across every Bash/Edit/Write call.
  Mitigation: every hook ships with a bats latency test (<100ms) gating
  shipping.
- Schema lock-in. Claude Code hook input/output schemas have shifted
  historically (HTTP type added Feb 2026). Mitigation: hooks parse via `jq`,
  not raw stdin; jq queries are forward-compatible.
- Runaway hook loops possible (Stop hook re-triggering Claude → re-trigger
  Stop). Mitigation: Hook 3 returns JSON, not free-form prompts; the 30s
  timeout caps recursion blast radius.
- Debugging difficulty when a hook silently mangles output. Mitigation:
  every hook ends in `exit 0` or `exit 2` explicitly; tests assert exit
  codes. `bin/check-hooks.sh` validates installation across all 5.

**Follow-ups:**
- After 4 weeks of usage, audit `.planning/skill-observations/` logs to see
  which hooks fire most often. Feed the data into the meta-observer skill
  (action plan §4.3) when it ships.
- If false-positive rate on Hook 3 exceeds 10%, revisit the prompt or
  add per-project allowlist.
- Linux-side: the bash + jq stack runs on Linux too; no porting needed for
  the hooks themselves. Only the LaunchAgent scheduling (Phase 4) needs
  the systemd-user sibling.

## References

- Synthesis report §3: hooks (Sah + Damle): `tooling-research-2026-05-02-batch2.md`
- Hand-off prompt Phase 2 spec
- [Vikas Sah — Agent Hooks Are Claude Code's Most Powerful Feature](https://engineeratheart.medium.com/agent-hooks-are-claude-codes-most-powerful-feature-and-almost-nobody-uses-them-d88d64f6172d)
- [Ketan Damle — Claude Code Hooks: Automate What Claude Should Always Do](https://medium.com/@koriigami/claude-code-hooks-automate-what-claude-should-always-do-d1cd4b031a30)
- Live: `templates/.claude/hooks/`, `templates/claude-settings.json`, `~/.claude/hooks/commitment-reinject.sh`, `tests/hooks/`, `bin/check-hooks.sh`
