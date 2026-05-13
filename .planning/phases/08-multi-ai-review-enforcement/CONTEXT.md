# Phase 08 — Multi-AI plan review enforcement

**Migration:** 0005-multi-ai-plan-review-enforcement
**Version bump:** 1.9.0 → 1.9.1
**Date opened:** 2026-05-13
**Predecessor:** Migration 0010 (post-process GSD section markers, 1.8.0 → 1.9.0)
**Decision record:** ADR 0018 — Multi-AI plan review enforcement (accepted 2026-05-12)
**Goal:** Promote the multi-AI plan review (`/gsd-review`, produced `{phase}-REVIEWS.md`) from a passively-installed gsd-patch slash command into a **structurally enforced contract gate** that blocks code-touching edits during execution if the active phase has `*-PLAN.md` files but no `*-REVIEWS.md`. Stop the drift observed in cparx phases 04.9 → 05-handover.

---

## Background

The AgenticApps workflow has three review touchpoints:

| # | Touchpoint | When | Gating | Output |
|---|---|---|---|---|
| 1 | Multi-AI plan review (`/gsd-review`) | Pre-execution | **Not enforced** (gsd-patch slash command, no gate) | `{padded_phase}-REVIEWS.md` |
| 2 | Stage 1 spec review (gstack `/review`) | Post-execution | Enforced via skill gate | `REVIEW.md` (Stage 1 section) |
| 3 | Stage 2 code-quality review (`superpowers:requesting-code-review`) | Post-execution | Enforced via skill gate | `REVIEW.md` (Stage 2 section) |

Audit of `factiv/cparx/.planning/phases/` on 2026-05-12 surfaced:

- Phases 01, 02, 03, 04, 04.5, 04.8 — REVIEWS.md produced
- Phases 03.5, 03.6, 04.6, 04.7 — REVIEWS.md missing
- Phases 04.9, 04.10, 04.11, 04.12, 04.13, 05 — REVIEWS.md permanently absent

**Eight consecutive phases proceeded to execution without the multi-AI plan review.** fx-signal-agent's single phase showed the same pattern. The post-execution skill-gated reviews fired every time. The pre-execution multi-AI review didn't — nothing detected its absence.

The fix is structural, not behavioural. A PreToolUse hook fired on `Edit|Write` matches the existing programmatic-hooks architecture from migration 0004 (ADR 0015) and can run in sub-100ms.

---

## Scope (must-have for this phase)

1. **Hook script** `templates/.claude/hooks/multi-ai-review-gate.sh` — vendored, executable, POSIX-bash 3.2+, sub-100ms latency. Detects active phase via `.planning/current-phase` symlink, finds `*-PLAN.md` and `*-REVIEWS.md` under `maxdepth 2`, blocks on missing/stub REVIEWS.md, allows on planning-artifact edits, allows when no active phase. **Already drafted** in `templates/.claude/hooks/multi-ai-review-gate.sh` (86 LOC), needs harness coverage and security pass.

2. **Migration 0005** — installs the hook into consumer projects, wires it into `.claude/settings.json` PreToolUse hooks array via `jq` (idempotent), bumps scaffolder version 1.9.0 → 1.9.1, records the new gate in `docs/workflow/ENFORCEMENT-PLAN.md` if vendored. **Already drafted** in `migrations/0005-multi-ai-plan-review-enforcement.md` (122 LOC), rebased to 1.9.x in commit `520216a`.

3. **Contract metadata** — `templates/config-hooks.json` gains `pre_execute_gates.multi_ai_plan_review` block; `docs/ENFORCEMENT-PLAN.md` gains a row in the planning-gates table. **Already drafted**; carried across in this phase.

4. **Test harness** — `migrations/test-fixtures/0005/{scenario}/{input,expected}/` with 4-5 scenarios covering the hook's decision matrix. `test_migration_0005()` stanza in `migrations/run-tests.sh` runs the hook script against fixture JSON inputs and asserts the expected exit code + stderr message.

5. **Skill version + CHANGELOG** — `skill/SKILL.md` bumped 1.9.0 → 1.9.1; `CHANGELOG.md` gains a `[1.9.1] — Unreleased` section directly above `[1.9.0]`.

6. **Phase artifacts** — RESEARCH.md, PLAN.md, REVIEWS.md (multi-AI dogfood), REVIEW.md (Stage 1 + Stage 2), SECURITY.md (CSO), VERIFICATION.md.

## Won't-do (explicit scope cuts)

- **Backfill of missed phases.** Hook gates new phases. Phases that already shipped without REVIEWS.md are not retroactively blocked or annotated.
- **Reviewer-CLI installation.** The migration's pre-flight verifies ≥2 CLIs are present. Installation is the user's responsibility (separate setup track).
- **Hook for projects without GSD.** If `.planning/current-phase` symlink is absent, the hook returns 0 immediately. Non-GSD repos are unaffected.
- **Changes to the `/gsd-review` slash command body.** Touchpoint 1's content is owned by `templates/gsd-patches/patches/workflows/review.md`. Untouched in this phase.
- **Hook 5 (commitment re-injector) coordination.** Hook 5 is global; this is per-project. They don't interact.

## Open questions (resolve before PLAN.md)

| # | Question | Tentative answer (to be challenged in RESEARCH.md) |
|---|---|---|
| Q1 | PreToolUse vs PostToolUse vs SessionStart? | PreToolUse — same model as existing hooks (4 of 5 already use it). |
| Q2 | Match on `Edit|Write|MultiEdit` or just `Edit|Write`? | Edit\|Write only — MultiEdit is rare and adds matcher cost. |
| Q3 | Override surface — env var alone, sentinel alone, or both? | Both — env var for session-scoped escape, sentinel for committed-to-git audit trail. |
| Q4 | Reviewer-presence policy — ≥2 CLIs, ≥1 CLI, or allowlist? | ≥2 CLIs at pre-flight time. Catches the "only gemini installed" foot-gun before the hook ships. |
| Q5 | REVIEWS.md stub detection — line count, file size, or content keyword? | Line count `< 5` ⇒ warn-only (exit 0). Empty-stub stricter than content-quality gate. |
| Q6 | Planning-artifact bypass scope — which basenames? | `*PLAN.md`, `*PLAN-*.md`, `*REVIEWS.md`, `ROADMAP.md`, `PROJECT.md`, `REQUIREMENTS.md`, `*CONTEXT.md`, `*RESEARCH.md`. Already in draft. |

## Decisions resolved (locked, do not relitigate)

- **Adopt PreToolUse + Edit|Write matcher** (Q1, Q2). Matches existing hooks 1-5 layout. RESEARCH.md will document the rejected alternatives.
- **Dual override surface — env var + sentinel file** (Q3). The env var is the session escape; the sentinel is the committed audit trail. ADR 0018 records this as auditable-by-design.
- **≥2 reviewer CLIs at pre-flight, not at hook-fire time** (Q4). The hook should not stat external binaries on every Edit/Write call (latency). The pre-flight check is one-shot at migration apply.
- **Line-count `< 5` ⇒ warn-only, not block** (Q5). A stub REVIEWS.md still demonstrates that the review ritual happened; the hook is enforcing presence-of-process, not quality-of-content. Stage 1/2 reviews are the quality gates.
- **maxdepth 2** for the `find` calls. Phases have `*-PLAN.md` directly under the phase dir or one level down (e.g. `executor-1-PLAN.md`). Anything deeper is non-phase content.
- **Migration to be shipped through the full GSD pipeline** including a real `/gsd-review` of THIS phase's plan. This is the dogfood test — the gate must fire on its own creation phase.

## Dependencies

**Upstream (already shipped, must remain available):**
- Migration 0000 — `.claude/settings.json` exists (bootstrapped by Step 6 since PR #9).
- Migration 0004 — programmatic-hooks-layer (ADR 0015) establishes the hook taxonomy.
- Migration 0010 — current scaffolder head at 1.9.0.

**External:**
- `templates/gsd-patches/patches/workflows/review.md` — defines the `/gsd-review` slash command. This phase does NOT modify it but the hook's pre-flight checks for `~/.claude/get-shit-done/commands/gsd-review.md` to detect installation.
- ≥2 reviewer CLIs in `$PATH`: `gemini`, `codex`, `claude`, `coderabbit`, `opencode`. Pre-flight enforces.

**Downstream (this phase enables / unblocks):**
- Future phases gain structurally enforced multi-AI plan review.
- PR #12 (carry-over 0005-0007) loses its 0005 slice — once this PR lands, the carry-over PR's body should be updated to drop the 0005 row.

---

## Acceptance criteria (goal-backward inputs for VERIFICATION.md)

- **AC-1** — Hook script vendored at `templates/.claude/hooks/multi-ai-review-gate.sh`, executable bit set, runs cleanly under `/usr/bin/env bash` on macOS bash 3.2 and Linux bash 5+.
- **AC-2** — Migration 0005 applies cleanly from a 1.9.0 baseline; idempotent re-apply is a no-op; rollback fully reverses Step 1 + Step 2 + Step 3.
- **AC-3** — Hook latency p95 < 100ms across all fixture scenarios. Measured via `/usr/bin/time -p` × 100 iterations.
- **AC-4** — `migrations/run-tests.sh` gains a `test_migration_0005()` stanza with ≥ 8 assertions covering: no-phase allow, missing-REVIEWS block, present-REVIEWS allow, stub-REVIEWS warn-only, env-var override allow, sentinel override allow, planning-artifact-edit allow, non-Edit-tool allow.
- **AC-5** — Hook never reads beyond `.planning/current-phase` symlink-target's `maxdepth 2`. No shell injection vectors via filename. Confirmed by CSO audit + a fixture with a hostile filename.
- **AC-6** — `templates/config-hooks.json` `pre_execute_gates.multi_ai_plan_review` block valid JSON, parses with `jq empty`.
- **AC-7** — `docs/ENFORCEMENT-PLAN.md` gains a row in the planning-gates table that references the gate's evidence requirement.
- **AC-8** — `skill/SKILL.md` `version: 1.9.1`; `CHANGELOG.md` `[1.9.1] — Unreleased` section with at minimum a `### Added` block.
- **AC-9** — `{padded_phase}-REVIEWS.md` produced for THIS phase by `/gsd-review` (dogfood self-test) OR explicit documentation in REVIEWS.md if reviewer CLIs are unavailable in this environment.
- **AC-10** — Stage 1 review (gstack `/review`): no BLOCK findings; FLAGs prose-addressed. Stage 2 review (independent reviewer agent): no BLOCK findings; FLAGs prose-addressed or deferred to follow-up phase. CSO review (`/cso`): no Critical findings; High findings either fixed or documented.

---

## Threat model preview (full version in PLAN.md)

| Threat | Surface | Mitigation |
|---|---|---|
| **Filename command injection** | `FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path')` then used in `basename` and `case` | jq output is a single string; `basename` and `case` are safe glob matchers. No `eval`, no command substitution on `$FILE`. |
| **Symlink races in `readlink` lookup** | `.planning/current-phase` could be swapped between `readlink` and `find` | Worst case: hook reads stale phase, blocks an edit that shouldn't be blocked. Self-healing on next invocation. |
| **Hostile phase-dir contents (race-on-find)** | A symlink-target dir with crafted filenames | `find -maxdepth 2 -name "*-PLAN.md"` ignores hidden files and does not execute filenames. |
| **Override-sentinel committed by mistake** | `.planning/current-phase/multi-ai-review-skipped` accidentally checked in | Detectable via `git log -- '*/multi-ai-review-skipped'`. ADR 0018 documents the audit-trail design. |
| **PATH manipulation in pre-flight CLI count** | `command -v gemini` etc. could trigger a malicious binary | Pre-flight runs once at migration-apply; the binary is not executed, only the count is read. |
| **REVIEWS.md size DoS** | A 10GB REVIEWS.md could choke `wc -l` | `wc -l` is streaming and constant memory. Worst case is a few seconds of CPU on a hook invocation — well within the hook timeout. |
| **Reviewer-CLI output trust** | `/gsd-review` writes REVIEWS.md from CLI outputs; this hook does not parse the content. Trust boundary preserved. | No mitigation needed at hook layer; ADR 0018 records that REVIEWS.md content is reviewer-trusted, not reader-trusted. |

Full threat decomposition + STRIDE matrix in PLAN.md.
