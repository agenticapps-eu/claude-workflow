# ADR 0018 — Multi-AI plan review enforcement

**Status:** Accepted
**Date:** 2026-05-12
**Supersedes:** —
**Superseded by:** —

## Context

The AgenticApps workflow has three review touchpoints:

1. **Pre-execution multi-AI plan review** — `/gsd-review` invokes gemini, codex, claude (separate session), coderabbit, opencode in sequence against the phase's `*-PLAN.md` files. Output: `{padded_phase}-REVIEWS.md`. Adversarial review catches plan-level blind spots before any code is written.
2. **Post-execution Stage 1 spec review** — `gstack /review`. Output: `REVIEW.md`. Catches spec drift.
3. **Post-execution Stage 2 code-quality review** — `superpowers:requesting-code-review` (independent reviewer agent). Output: Stage 2 section in `REVIEW.md`. Catches code-quality drift.

Touchpoints 2 and 3 are enforced — they appear in the ENFORCEMENT-PLAN.md gate table, the SKILL.md commitment ritual, and the contract JSON block in templates/config-hooks.json. They fire as skills, not slash commands, so they cannot be silently dropped.

Touchpoint 1 — the multi-AI plan review — is **not enforced**. It exists only as a gsd-patch template at `templates/gsd-patches/patches/workflows/review.md` and an installed slash command at `~/.claude/get-shit-done/commands/gsd-review.md`. No gate, no skill, no contract entry.

## Observed failure mode

Audit of cparx (`factiv/cparx/.planning/phases/`) on 2026-05-12 showed the following pattern:

- Phases 01, 02, 03, 04, 04.5, 04.8 — REVIEWS.md produced
- Phases 03.5, 03.6, 04.6, 04.7 — REVIEWS.md missing
- Phases 04.9, 04.10, 04.11, 04.12, 04.13, 05 — REVIEWS.md permanently absent

Eight consecutive phases — including the entire 05-handover — proceeded to execution without the multi-AI plan review. fx-signal-agent's only phase had the same pattern: no REVIEWS.md, post-execution REVIEW.md present.

The post-execution reviews fired in every phase (because they are skill-gated). The pre-execution multi-AI review did not, because nothing detected its absence.

## Decision

Promote the multi-AI plan review from a gsd-patch slash command to an enforced contract gate, with three coordinated changes:

1. **Add a programmatic hook** (`.claude/hooks/multi-ai-review-gate.sh`, PreToolUse on `Edit|Write`) that blocks code-touching edits during a phase if the phase has `*-PLAN.md` files but no `*-REVIEWS.md`. Latency sub-100ms. Override available via `GSD_SKIP_REVIEWS=1` or a per-phase sentinel for emergencies. Edits to planning artifacts themselves (PLAN.md, ROADMAP.md, REQUIREMENTS.md, CONTEXT.md, RESEARCH.md) bypass the gate to avoid deadlock.

2. **Add a contract entry** under `pre_execute_gates.multi_ai_plan_review` in templates/config-hooks.json and a corresponding row in ENFORCEMENT-PLAN.md. Required evidence: `{padded_phase}-REVIEWS.md` exists and is non-trivial.

3. **Update the conceptual layer** in skill/SKILL.md — add `/gsd-review` to the Pre-execution gate sequence, add "Skipping `/gsd-review`" as failure mode 9 with the cparx-phase-04.9-through-05 incident as the cautionary tale.

## Consequences

**Positive:**
- Multi-AI plan review becomes structurally hard to skip. Any project on workflow ≥ 1.5.1 gets the hook automatically via `/setup-agenticapps-workflow` or `/update-agenticapps-workflow`.
- Drift pattern observed in cparx cannot recur — the hook detects it at the tool-call boundary.
- Backfill of missed reviews remains optional. The hook does not block new code in a project that already shipped phases without reviews; it only blocks NEW phases that planned without reviewing.

**Negative:**
- An additional hook execution per Edit/Write tool call. Latency budget < 100ms is achievable (hook is mostly readlink + a couple of finds with `-maxdepth 2`).
- Edits to a phase between planning and review-completion will be blocked. This is by design but adds one extra step for fast iterations.
- Projects that don't use GSD or have no `.planning/current-phase/` symlink see the hook return 0 (allow) immediately — no functional impact on non-GSD work.

**Override surface (explicit and auditable):**
- `GSD_SKIP_REVIEWS=1` environment variable — session-scoped, leaves no on-disk trace.
- `touch .planning/current-phase/multi-ai-review-skipped` — phase-scoped, leaves a sentinel file. Use only for genuine emergencies; the sentinel is committed to the phase directory so future audits can see when overrides were used.

## Migration

Migration `0005-multi-ai-plan-review-enforcement.md` installs the hook, updates the JSON contract, edits ENFORCEMENT-PLAN.md and SKILL.md, bumps workflow version 1.9.0 → 1.9.1 (rebased from the original 1.5.0 → 1.5.1 target — see PR #12 for the rebase context). Idempotent re-apply is a no-op (Step 2's jq merge guards on existing matcher presence). Test fixtures at `migrations/test-fixtures/0005/` (13 scenarios covering every decision branch, including malformed-JSON fail-open and non-`.planning/` PLAN.md non-bypass).

## Related

- ADR 0014 — GSD bug fixes (touched `/gsd-review` opencode invocation; did not address enforcement gap)
- ADR 0015 — Programmatic hooks layer (this hook is hook 6 in that taxonomy)
- Templates: `templates/gsd-patches/patches/workflows/review.md` (the slash-command definition; unchanged)
