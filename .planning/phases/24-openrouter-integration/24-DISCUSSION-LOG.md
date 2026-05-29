# Phase 24 — OpenRouter integration kit — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered
> and the auto-selection rationale.

**Date:** 2026-05-29
**Phase:** 24-openrouter-integration
**Mode:** `--auto` (single-pass; recommended options auto-selected per PROMPT B's stated defaults + brainstorming output)
**Areas discussed:** Versioning · Helper-API surface · Cache-token field source · Pricing-data scope · Anthropic-SDK runbook scope · Monitor delivery model · Monitor wrapping + envs · INIT.md surface · ADR & phase numbering · Test surface · ROADMAP gap

---

## Area: Versioning

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Bump claude-workflow + add-observability; no migration | Additive deliverables; existing projects adopt via runbook | ✓ |
| (b) Bump claude-workflow only; treat add-observability changes as cosmetic | Wouldn't surface that 3 new template files ship — dishonest | |
| (c) Migration + minor bumps | No existing project state needs migration; ceremony with no payload | |

**Auto-selected:** (a) — `[auto] Versioning → claude-workflow 1.18.0→1.19.0 + add-observability 0.7.0→0.8.0, no migration (PROMPT B default; honours versioning-tracks-migrations invariant — additive template changes earn a minor bump)`

**Notes:** Verified prompt's `1.18.0 → 1.19.0` matches current state. Prompt's `0.6.0 → 0.7.0` for add-observability is off-by-one (it's already at 0.7.0); locked at 0.7.0→0.8.0.

---

## Area: Helper-API surface

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Injected `LogEventFn` (prompt's shape, corrected imports) | Testable; destination-agnostic; matches §10.6 | ✓ |
| (b) Direct `import { logEvent } from "./lib-observability"` | Tighter call site; harder to mock; couples helper to module | |
| (c) Class-based wrapper | Overkill for a 30-line function | |

**Auto-selected:** (a) — `[auto] Helper API → injected LogEventFn (PROMPT B's design with three import corrections: import Envelope from ./lib-observability; declare LogEventFn locally; guard cache_ratio against div-by-zero)`

**Notes:** Prompt's reference file `observability.ts` is actually `lib-observability.ts`. Prompt's `import type { LogEventFn } from "./index"` would not compile — no `./index.ts` exists in templates. Corrections recorded in CONTEXT D-04.

---

## Area: Cache-token field source-of-truth (OQ-2 in prompt)

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Trust prompt's path `usage.prompt_tokens_details.cached_tokens` + defensive `?? 0` | OpenAI documents this; OpenRouter mirrors; confidence high | ✓ |
| (b) Cross-family read of `~/Sourcecode/factiv/.../SPIKE-RESULT.md` | Violates family-boundary rule unless explicit | |
| (c) context7 + OpenRouter docs verification at execute time | Worth doing anyway during runbook authoring (Phase 24.2) | partial |

**Auto-selected:** (a) + (c) belt-and-braces — `[auto] Cache-token field → trust prompt's path with ?? 0 defensive default; verify via OpenRouter docs during runbook authoring (Phase 24.2 context7 query). If field path ever drifts, helper silently reports 0 cache hits — detectable in Axiom by cross-checking OpenRouter dashboard.`

**Notes:** OQ-2 resolution per CONTEXT D-05.

---

## Area: Pricing-data scope (OQ-1 in prompt)

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Ship bundled `pricing.json` | Rots immediately; new models weekly; duplicates Sentry's calc | |
| (b) No pricing data; rely on Sentry AI Monitoring + OpenRouter `/generation` | Canonical source owned by upstream | ✓ |
| (c) Per-project pricing override | YAGNI for v0.8.0; can add later if a project needs it | |

**Auto-selected:** (b) — `[auto] Pricing → no pricing.json bundled; Sentry AI Monitoring computes cost; per-call cost on demand via OpenRouter /api/v1/generation?id=<x>; credit-check Worker reads canonical spend from /api/v1/key (PROMPT B default).`

**Notes:** OQ-1 resolution per CONTEXT D-06.

---

## Area: Anthropic-SDK runbook scope (G3 in brainstorming)

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Document Anthropic path generically as a parallel option | Runbook handles both SDKs without speculating on consumers | ✓ |
| (b) Ship Anthropic-specific helper code too | No current consumer; YAGNI | |
| (c) Skip Anthropic entirely; OpenAI-only runbook | Locks out fxsa's potential PROMPT C0 Option 2 | |

**Auto-selected:** (a) — `[auto] Anthropic runbook → documented generically alongside OpenAI; "if your project uses @anthropic-ai/sdk, the same anthropicIntegration pattern applies"; no Anthropic-specific code ships`

**Notes:** G3 resolution per CONTEXT D-07.

---

## Area: Monitor delivery model (OQ-3 in prompt)

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Standalone scaffold `templates/openrouter-monitor/` | Clear mental model; forkable; no CLI maintenance tax | ✓ |
| (b) Subcommand `add-observability deploy-openrouter-monitor` | Tighter coupling; CLI surface grows | |
| (c) In-tree per-stack (each stack carries its own monitor) | Duplication × N stacks; only Cloudflare Worker is appropriate runtime today | |

**Auto-selected:** (a) — `[auto] Monitor → standalone scaffold at add-observability/templates/openrouter-monitor/ (PROMPT B default).`

**Notes:** OQ-3 resolution per CONTEXT D-08.

---

## Area: Monitor wrapping + env vars (G1, D-10)

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Wrap with `withCronMonitor` from ADR-0029; env vars verbatim from prompt | Reuses Phase 23 work; consistent naming | ✓ |
| (b) Hand-roll Sentry check-in lifecycle in monitor handler | Reinvents ADR-0029; pre-callback failure mode would skip credit check | |
| (c) Skip `withCronMonitor` (no heartbeat on the monitor itself) | A stalled monitor wouldn't self-alert — exactly what ADR-0029 prevents | |

**Auto-selected:** (a) — `[auto] Monitor wrapping → withCronMonitor + verbatim env names (OPENROUTER_API_KEY, OPENROUTER_WARNING_RATIO=0.85, OPENROUTER_CRITICAL_RATIO=0.95); cron schedule */15 * * * *; keys:read scope documented in README.`

**Notes:** G1 + D-09 + D-10 resolution. The monitor's own heartbeat is critical — if the credit check itself fails silently for a week, the budget alarm never fires.

---

## Area: INIT.md surface

| Option | Description | Selected |
|--------|-------------|----------|
| (a) New §5 "Optional: LLM observability" with consent gate 4 (detection grep + 3 actions) | Matches existing consent-gate convention; opt-in | ✓ |
| (b) Always-on auto-instrumentation during init | Violates the consent-gate philosophy | |
| (c) Skip INIT.md surface; runbook only | New greenfield projects miss the easy path | |

**Auto-selected:** (a) — `[auto] INIT.md → new §5 "Optional: LLM observability" with consent gate 4; trigger = grep openai|@anthropic-ai/sdk in package.json AND grep -r openrouter.ai src/; default action = skip on --yes (PROMPT B + matches existing INIT.md gate convention).`

**Notes:** D-13 resolution.

---

## Area: ADR + phase numbering reconciliation

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Phase 24 / ADR-0030 / add-observability 0.7.0→0.8.0 | Next-available across all three counters | ✓ |
| (b) Use prompt's numbers verbatim (Phase 23 / ADR-0029 / 0.6.0→0.7.0) | All three collide with merged Phase 23 work | |
| (c) Skip phase artifacts entirely; ship as bare PR | Breaks the gsd convention; loses audit trail | |

**Auto-selected:** (a) — `[auto] Numbering → Phase 24 / ADR-0030 / add-observability 0.7.0→0.8.0 / claude-workflow 1.18.0→1.19.0. Reconciliation table in CONTEXT.md "Sequencing note" section.`

**Notes:** Prompt was authored before PROMPT A merged on 2026-05-29; collisions are mechanical not substantive.

---

## Area: Test surface

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Per-stack helper tests × 3 + monitor tests; reuse existing harness | TDD discipline; ~21 new cases; no harness changes | ✓ |
| (b) Single shared test file with mocked module loading | Tightly couples 3 stack copies; brittle | |
| (c) Skip helper tests (it's "thin enough") | Violates workflow's TDD enforcement | |

**Auto-selected:** (a) — `[auto] Tests → 3 helper test files + 1 monitor test file; ~21 new cases; ride existing run-template-tests.sh harness; RED→GREEN commit discipline per task per agenticapps-workflow skill.`

**Notes:** D-15 resolution.

---

## Area: ROADMAP-bootstrap gap

| Option | Description | Selected |
|--------|-------------|----------|
| (a) Defer ROADMAP bootstrap to a separate phase; write Phase 24 artifacts directly | Phase 23 precedent; keeps PR focused on OpenRouter work | ✓ |
| (b) Bootstrap minimal ROADMAP covering Phases 1–24 inline | Scope creep; multi-hour task that belongs in its own phase | |
| (c) Author ADR-0031 documenting the bypass as deliberate | Cheaper than (b) but doesn't unblock /gsd-progress; can still be done later | |

**Auto-selected:** (a) — `[auto] ROADMAP → defer to its own phase; Phase 24 writes artifacts directly to .planning/phases/24-openrouter-integration/ per Phase 23 precedent; gap noted in Deferred Ideas for the next session.`

**Notes:** D-16 resolution. Repo-workflow gap remains the handoff's "highest leverage" candidate but it does not belong in this feature PR.

---

## Claude's Discretion

The following sub-choices were left to Claude's judgment during implementation (no user-facing decision):

- Exact wording of the runbook's PII callout (must be visually loud; will use a `> ⚠️ **PII GATE**` block).
- Exact wording of consent-gate-4 prompt in INIT.md (will mirror gates 1–3 style).
- Test-fixture format and naming (will follow `cron-monitor.test.ts` patterns from Phase 23).
- README.md tone for `openrouter-monitor/` scaffold (concise, README-as-runbook style).
- Whether to verify Sentry `openAIIntegration` import path via context7 at Phase 24.2 — yes, will verify (low-cost insurance).

## Deferred Ideas

(See CONTEXT.md `<deferred>` block for the full list. Carried forward unchanged from there.)
