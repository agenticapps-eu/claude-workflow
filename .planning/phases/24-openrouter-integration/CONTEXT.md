# Phase 24 — OpenRouter integration kit (claude-workflow 1.19.0)

> **STATUS: RESOLVED — ready for `/gsd-plan-phase 24`.**
> All open questions locked on 2026-05-29 via `--auto` discuss-phase
> (PROMPT B was already prescriptive; this CONTEXT records the
> brainstorming output, prompt corrections, and numbering reconciliation).
> Decisions are binding through plan + execute.

**Branch**: `feat/openrouter-integration-v1.19.0` (cut from `main@7904681`, 2026-05-29).
**Spec target**: `agenticapps-workflow-core@v0.4.0` — no spec change. §10.6 destination-independence covers all four deliverables.
**Version bump (locked per D-01)**: `claude-workflow 1.18.0 → 1.19.0` minor (additive — new helper + new template + new runbook + INIT.md surface). `add-observability 0.7.0 → 0.8.0` minor (new helper across 3 stacks + new openrouter-monitor scaffold). **No migration** — purely additive. Existing projects adopt via the runbook.
**Date opened**: 2026-05-29
**Date resolved**: 2026-05-29
**Hand-off source**: PROMPT B (operator-supplied 2026-05-28; revised 2026-05-28 to drop the raw-fetch `wrapLLMCall` helper as YAGNI — both factiv LLM consumers use the OpenAI SDK).

## Sequencing note — prompt numbering vs reality

PROMPT B was authored before PROMPT A (Phase 23) merged. Three numbering items in the prompt are off-by-one against the merged repo state. Resolution captured here:

| Item | Prompt said | Reality at 7904681 | Locked |
|------|-------------|--------------------|--------|
| Phase number | 23 | 23 = `observability-followups` (merged) | **24** |
| ADR number | 0029 | 0029 = `cron-monitor SDK composition` (merged) | **0030** |
| `add-observability` version | 0.6.0 → 0.7.0 | already at 0.7.0 | **0.7.0 → 0.8.0** |
| `claude-workflow` version | 1.18.0 → 1.19.0 | at 1.18.0 | **1.18.0 → 1.19.0** ✓ |

Prompt's `Read first` list referenced `add-observability/templates/ts-cloudflare-worker/observability.ts` — that file is actually named `lib-observability.ts`. Correction recorded in D-04.

<decisions>
## Resolved decisions (D-01 — D-16)

> **Source.** All decisions auto-resolved during `--auto` discuss-phase
> 2026-05-29. PROMPT B prescribed defaults for the 3 explicit open questions
> (OQ-1, OQ-2, OQ-3 in the prompt); the brainstorming pass surfaced six
> additional gap decisions (G1–G6) plus the three numbering reconciliations
> above. See `24-DISCUSSION-LOG.md` for the per-decision option matrix.

**D-01 — Version bumps.** `claude-workflow 1.18.0 → 1.19.0` minor; `add-observability 0.7.0 → 0.8.0` minor; no migration; CHANGELOG `[1.19.0]` entry; bump `skill/SKILL.md` and `add-observability/SKILL.md` frontmatter `version:` fields. Existing projects adopt the new helper + monitor via the runbook (manual copy or via INIT for greenfield). *(OQ-1 → bumps; aligned with handoff's "versioning tracks migrations" invariant — these are template-side additions, not migration-engine fixes, so a minor bump is honest.)*

**D-02 — Phase scope = four deliverables, batched into one phase / one PR.**
1. `recordLLMResponseMeta` helper across 3 TS stacks (worker, pages, supabase-edge).
2. `add-observability/openrouter-integration.md` runbook.
3. `add-observability/templates/openrouter-monitor/` standalone Worker scaffold.
4. `docs/decisions/0030-openrouter-integration-sdk-first.md` ADR + `init/INIT.md` Phase 5 §"Optional: LLM observability" + CHANGELOG + version bumps.

Per-deliverable PR ceremony would dwarf per-deliverable implementation cost. All four share the same code-review surface (helper + monitor + docs), the same security review (LLM key handling), and the same destination-independence verification.

**D-03 — SDK-first only. No raw-fetch `wrapLLMCall`.** PROMPT B's revision deletes the raw-fetch wrapper an earlier draft specified. Both factiv consumers (callbot at HEAD, fx-signal-agent post-PROMPT C0) use the OpenAI SDK. Sentry AI Monitoring's `openAIIntegration` covers per-call spans (model/tokens/cost/latency). The only gaps the SDK integration misses are rate-limit headroom + cache-read ratio + running budget — those are covered by D-04 (helper) and D-08 (monitor Worker). No raw-fetch consumer exists; YAGNI applies. If a future project genuinely needs raw-fetch instrumentation, that's a new prompt against a new phase.

**D-04 — Helper signature: dependency-injected `LogEventFn` (testability + §10.6).** Final shape:

```ts
// add-observability/templates/<stack>/llm-response-meta.ts
import type { Envelope } from "./lib-observability";

export type LogEventFn = (envelope: Envelope) => void;

export interface LLMUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  prompt_tokens_details?: { cached_tokens?: number };
}

export interface LLMCallMetaContext {
  model: string;
  service?: string; // defaults to "openrouter"
}

export function recordLLMResponseMeta(
  logEvent: LogEventFn,
  raw: Response,
  usage: LLMUsage,
  ctx: LLMCallMetaContext,
): void {
  const cached = usage.prompt_tokens_details?.cached_tokens ?? 0;
  const prompt = usage.prompt_tokens ?? 0;
  logEvent({
    event: "llm.call_meta",
    severity: "info",
    attrs: {
      model: ctx.model,
      service: ctx.service ?? "openrouter",
      rate_remaining: raw.headers.get("x-ratelimit-remaining"),
      rate_reset: raw.headers.get("x-ratelimit-reset"),
      cached_tokens: cached,
      prompt_tokens: prompt,
      completion_tokens: usage.completion_tokens ?? 0,
      cache_ratio: prompt > 0 ? cached / prompt : 0,
    },
  });
}
```

Three corrections vs the prompt's example:
1. Import the `Envelope` type from `./lib-observability` (the prompt's `./index` doesn't exist in templates).
2. Declare `LogEventFn` locally as `(envelope: Envelope) => void` rather than importing it (it's not exported).
3. Guard `cache_ratio` against divide-by-zero (`prompt > 0 ? ... : 0`) rather than truthy check on `usage.prompt_tokens` (the prompt's `usage.prompt_tokens ?` works when `prompt_tokens` is 0 but is less explicit).

Helper ships in `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`. Skip `ts-react-vite` (browser doesn't hold OpenRouter keys; proxies through a backend). Skip `go-fly-http` (no Go LLM consumer yet; can be added when one exists).

**D-05 — Cache-token field path: `usage.prompt_tokens_details.cached_tokens` with `?? 0` defensive default.** OpenAI SDK against OpenRouter returns the OpenAI-compatible usage shape, where cached prompt tokens land at `prompt_tokens_details.cached_tokens`. Confidence high — OpenAI documents this; OpenRouter mirrors. If the field path ever drifts, the helper silently reports 0 cache hits, detectable in Axiom by comparing to OpenRouter dashboard. Defer fix to a follow-up PR if disagreement surfaces. *(OQ-2 resolution. We do **not** cross-family read `~/Sourcecode/factiv/fx-signal-agent/.../SPIKE-RESULT.md` — the family boundary rule applies, and the prompt's path is well-grounded enough to roll forward.)*

**D-06 — No bundled `pricing.json`.** Sentry AI Monitoring computes cost from its own pricing table; OpenRouter exposes per-call cost via `GET /api/v1/generation?id=<x>`. A bundled `pricing.json` would rot (new models ship weekly), duplicate Sentry's calc, and add a PR-per-new-model maintenance tax. The credit-check Worker (D-08) reads canonical spend via `GET /api/v1/key`, not a local table. *(OQ-1 resolution.)*

**D-07 — Runbook scope: document both `openAIIntegration` and `anthropicIntegration`, but generically.** The Anthropic SDK section is documented as a parallel path ("if your project uses `@anthropic-ai/sdk`, the same pattern applies"), not as a commitment to any specific consumer. fxsa's PROMPT C0 may or may not pick the Anthropic path — the runbook handles both without speculating on consumer choices.

**D-08 — Monitor delivery: standalone scaffold at `add-observability/templates/openrouter-monitor/`.** Not a subcommand (`add-observability deploy-openrouter-monitor`). Clearer mental model (it's a Worker you fork or copy into a monorepo, not a CLI side effect). Doesn't bloat the `add-observability` CLI surface that needs maintenance. *(OQ-3 resolution.)*

**D-09 — Monitor wraps with `withCronMonitor` from ADR-0029 (Phase 23).** Composition order: outer `withSentry(env)` → `withObservabilityScheduled` → `withCronMonitor` → handler. `cron-monitor.ts` lives in each stack's template dir already — the monitor Worker imports its own copy (standalone scaffold) rather than reaching across template boundaries. Slug auto-resolution from cron schedule per D6 of Phase 22.

**D-10 — Monitor env vars (verbatim from PROMPT B).**
- `OPENROUTER_API_KEY` — read-only, `keys:read` scope only (documented in README).
- `OPENROUTER_WARNING_RATIO` — default `0.85`.
- `OPENROUTER_CRITICAL_RATIO` — default `0.95`.
- Standard `SENTRY_DSN` + `AXIOM_*` per existing wrapper convention.

Cron schedule `*/15 * * * *` (every 15 min). README documents threshold tuning + key-scope rationale.

**D-11 — Monitor handler emits via project's standard wrapper.** `logEvent` + `captureError` go through the destinations registry (Sentry adapter + Axiom adapter). No second Sentry init in the monitor Worker — it shares the `Sentry.init` that the scheduled wrapper sets up. Per §10.6 destination-independence: zero hard-coded SDK calls in handler logic.

**D-12 — Error class hierarchy.** Two named errors emitted via `captureError`:
- `OpenRouterBudgetCriticalError(used_ratio)` — fires when `used_ratio >= OPENROUTER_CRITICAL_RATIO`.
- `OpenRouterHealthcheckFailedError(status)` — fires on non-2xx response from `/api/v1/key`.
- Warning band (`>= WARNING_RATIO` but `< CRITICAL_RATIO`) emits via `logEvent({event:"openrouter.credit_low", severity:"warning", attrs})` — not an exception (operator awareness, not pager).
- Every invocation emits `logEvent({event:"openrouter.credit_pulse", severity:"info", attrs:{used, limit, used_ratio}})` for Axiom time-series.

**D-13 — INIT.md Phase 5 surface: "Optional: LLM observability" section with consent gate 4.** Trigger: `grep package.json` for `openai` OR `@anthropic-ai/sdk` AND `grep -r openrouter.ai src/`. When matched, offer three actions:
- (a) insert `openAIIntegration({recordInputs:false, recordOutputs:false})` (or `anthropicIntegration`) into existing Sentry init.
- (b) copy `llm-response-meta.ts` into the stack-appropriate template-derived location.
- (c) skip — already configured / not needed.

Default to (c) on unattended `--yes` runs. Consent gate 4 follows the existing INIT.md gate convention (consent gates 1–3 already documented for wrapper/middleware/CLAUDE.md writes).

**D-14 — ADR number: 0030.** ADR-0029 = cron-monitor SDK composition (Phase 23). Next available is 0030. Title: `0030-openrouter-integration-sdk-first.md`. Records SDK-first decision + dropped `wrapLLMCall` as rejected alternative.

**D-15 — Test surface.**
- Per-stack helper test (3 files): `llm-response-meta.test.ts` × {worker, pages, supabase-edge}. Fixtures cover: cache-hit (cached_tokens > 0), cache-miss (cached_tokens == 0), missing usage fields (defensive defaults), missing rate-limit headers (header.get returns null), cache_ratio divide-by-zero safety.
- Monitor handler tests (1 file): `templates/openrouter-monitor/src/index.test.ts`. Fixtures cover: under WARNING (info pulse only), at WARNING (info + credit_low warn), at CRITICAL (info + critical error captured), 401 from `/api/v1/key` (HealthcheckFailedError), 500 from `/api/v1/key` (HealthcheckFailedError), `withCronMonitor` wrapping verification (handler runs even when DSN unconfigured).
- Existing harnesses run new tests: `add-observability/templates/run-template-tests.sh all` picks up the new files automatically.

Target: 3 helper tests × ~5 cases + 1 monitor test × ~6 cases ≈ **21 new test cases** on top of Phase 23's 253 template-test baseline.

**D-16 — ROADMAP bootstrap deferred.** PROMPT B references `/gsd-discuss-phase 0` (the prompt was written generically) but the repo has no `ROADMAP.md`. Phase 23 worked around this; Phase 24 carries the precedent. Bootstrap remains the highest-leverage workflow gap (per session-handoff.md) but belongs in its own phase — not slipped into a feature PR. Captured in Deferred Ideas for the next session.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Spec
- `~/Sourcecode/agenticapps/agenticapps-workflow-core/spec/10-observability.md` — §10.6 destination-independence (helper + monitor MUST honour); §10.7 host-discretion (no spec change in this phase).

### ADRs (current repo)
- `docs/decisions/0014-observability-architecture.md` — wrapper architecture (init/logEvent/captureError contract). Helper + monitor emit through this surface.
- `docs/decisions/0029-cron-monitor-sdk-composition.md` — `withCronMonitor` Guarded Shape A; monitor Worker uses this.

### Implementation references (current repo)
- `add-observability/SKILL.md` — dispatch table; bump frontmatter to 0.8.0.
- `add-observability/templates/ts-cloudflare-worker/lib-observability.ts` — canonical `Envelope` type, `logEvent` signature; helper imports `Envelope` from here. **NOTE**: prompt incorrectly referenced this as `observability.ts`; the actual filename is `lib-observability.ts`.
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts` (lines 1–30, 115+) — `withCronMonitor` import surface for the monitor Worker.
- `add-observability/templates/ts-cloudflare-worker/middleware.ts` — wrapper convention reference.
- `add-observability/templates/run-template-tests.sh` — harness picks up new tests automatically.
- `add-observability/init/INIT.md` — Phase 5 §"Optional: LLM observability" anchor.

### External docs (verify during execute)
- Sentry AI Monitoring: <https://docs.sentry.io/product/insights/ai/> — `openAIIntegration` + `anthropicIntegration` enablement, version-specific import paths for `@sentry/cloudflare`. context7 verify during Phase 24.2 (runbook authoring).
- OpenRouter API: <https://openrouter.ai/docs> — `GET /api/v1/key` (credit balance shape), `GET /api/v1/generation?id=` (per-call cost), `usage.prompt_tokens_details.cached_tokens` field path confirmation.

### Out-of-family (informational only; do NOT modify)
- `~/Sourcecode/factiv/callbot/apps/backend/src/llm/client.ts` — example SDK consumer.
- `~/Sourcecode/factiv/fx-signal-agent/apps/worker-agent/src/llm/client.ts` (post-PROMPT C0) — example SDK consumer.
- (NOT READ by this phase — family boundary applies. Names are listed so a future PROMPT C / PROMPT D author has the consumer-side reference.)
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`logEvent(envelope: Envelope)` + `captureError(err, envelope)`** from `lib-observability.ts` — the helper + monitor emit through these. Already destination-aware (logs vs errors role).
- **`Envelope = { event: string; severity?: Severity; attrs?: Record<string, unknown> }`** — the helper's `event: "llm.call_meta"` slots in cleanly.
- **`withCronMonitor` from `cron-monitor.ts` (line 115)** — the monitor Worker wraps its scheduled handler. Guarded Shape A guarantees the credit check still runs even if Sentry transport fails pre-callback.
- **Test harness `add-observability/templates/run-template-tests.sh all`** — green at 253 cases pre-Phase-24. Picks up new `.test.ts` files in each stack's template dir without harness changes.
- **`add-observability/init/INIT.md` Phase 5 framework** — already runs detection grep + offers consent-gated actions. The new "Optional: LLM observability" section reuses this scaffold (consent gate 4).

### Established Patterns
- **Per-stack template duplication** (vs shared library): each TS stack carries its own `lib-observability.ts`, `cron-monitor.ts`, etc. The helper follows this — three copies, one per stack. (Cost: ~150 LOC duplicated. Benefit: each stack's templates are self-contained and forkable.)
- **TDD via the template-test harness**: helper tests sit next to source (`*.test.ts`), monitor tests sit in the scaffold's `src/`. RED→GREEN commits per task.
- **§10.6 destination-independence**: helper takes `logEvent` by injection (not import) so callers can wire to any destination; monitor handler emits via project's wrapper (no second Sentry init).
- **PII default = redacted**: `recordInputs/Outputs: false` is the documented default for `openAIIntegration` — runbook's PII callout cements this as non-negotiable for callbot (PHI) and cparx (financial) classes of consumer.

### Integration Points
- Helper `import type { Envelope }` from `./lib-observability` in each stack's template (relative path stable across all 3 stacks).
- Monitor Worker imports `withCronMonitor` from its own local `cron-monitor.ts` (scaffold carries the file).
- INIT.md detection scan runs after Phase 4 (Sentry init detection), before Phase 6 (CLAUDE.md metadata). New §5.5 placement.
- CHANGELOG `[1.19.0]` entry under existing changelog structure (Added / Changed / Fixed).
</code_context>

<specifics>
## Specific Ideas

- The runbook's "PII callout" must be visually loud — recommend a `> ⚠️ **PII GATE**` callout block before the `recordInputs:true` discussion, with concrete examples (callbot = patient data; cparx = financial PII; fxsa = market signal — lower PII risk but still gated).
- Helper's `service` field default `"openrouter"` is correct for the dominant case but should be overridable for projects that route through Together.ai / Groq / direct Anthropic. The `service?: string` shape already allows this.
- Monitor's `keys:read`-scoped OpenRouter key is critical — a leak of the generation key (full scope) from a public-Worker URL would burn the budget cap. README must lead with this.
- Consider adding a `OPENROUTER_BUDGET_OVERRIDE` env var that lets ops override the budget cap reported by `/api/v1/key` (e.g., if OpenRouter reports the org-level cap but ops wants a per-project soft cap lower than that). **Decision**: defer to v0.9.0 — YAGNI for v0.8.0.
</specifics>

<deferred>
## Deferred Ideas

### Carried from Phase 23 (still in 0.8.0 candidate backlog)
- **WR-01** — Pages KV signal threading + add `signal?: AbortSignal` to `HealthzEnv.OBSERVABILITY_KV.get` type (advisory).
- **WR-02** — Go upstream body close in timeout branch (advisory).
- **WR-03 / A-01** — `_setWithMonitorForTest` null-restore branch (+ optional build-time gate) (advisory).
- **A-02** — Healthz `/healthz` default → `{ status }` only, opt into `?detail=true` (security advisory).

### New deferrals from this phase
- **Raw-fetch `wrapLLMCall` helper** — rejected per D-03 (no consumer; YAGNI). Revisit if a future project needs raw-fetch instrumentation against the OpenRouter HTTP API directly (e.g., a non-TS / non-Go stack, or a stack where the SDK doesn't compile).
- **Bundled `pricing.json` model→cost table** — rejected per D-06 (Sentry + OpenRouter own this).
- **Go stack helper** — no Go LLM consumer in scope. Add when one appears.
- **react-vite helper** — browser must NOT hold OpenRouter keys; proxies through a backend that gets the helper. Browser-side captures handled separately.
- **`OPENROUTER_BUDGET_OVERRIDE` ops override** — v0.9.0 candidate per Specifics.

### Workflow gaps (still highest leverage, still outside this PR's scope)
- **ROADMAP.md / STATE.md / REQUIREMENTS.md retroactive bootstrap** — unblocks `/gsd-progress`, `/gsd-audit-uat`, future-phase auto-advance. Belongs in its own phase. Phase 24 carries the Phase 23 precedent of writing artifacts directly.
- **GH Actions CI** — gate PRs on `migrations/run-tests.sh` + `templates/run-template-tests.sh all`. Independent of this PR.
- **Upstream `WithMonitor` contribution to `getsentry/sentry-go`** — out of repo scope.

### Scope-creep redirects from this phase's discussion
- None — discussion stayed within the four prompt-prescribed deliverables.
</deferred>

---

*Phase: 24-openrouter-integration*
*Context gathered: 2026-05-29 (--auto, single-pass)*
