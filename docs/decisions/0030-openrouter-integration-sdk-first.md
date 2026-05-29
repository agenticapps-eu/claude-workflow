# 0030 — OpenRouter integration: SDK-first

**Status**: Accepted  **Date**: 2026-05-29  **Phase**: 24-openrouter-integration

## Context

AgenticApps projects increasingly use OpenRouter as a unified LLM gateway. Two projects in-flight consume it via `new OpenAI({ baseURL: 'https://openrouter.ai/api/v1' })`:

- `factiv/callbot` (current).
- `factiv/fx-signal-agent` (post-PROMPT C0 migration).

Without observability instrumentation, four signals are invisible:

1. Per-call telemetry (model / tokens / cost / latency).
2. Rate-limit headroom (`x-ratelimit-remaining` / `x-ratelimit-reset` response headers).
3. Cache-read efficacy (`usage.prompt_tokens_details.cached_tokens` ratio).
4. Running budget (org-level spend against the OpenRouter cap).

The first is solved upstream by Sentry AI Monitoring. The other three need bespoke instrumentation that fits the existing wrapper architecture (ADR-0014) and the destination-independence contract (§10.6).

## Decision

Ship **four SDK-first deliverables** under `add-observability 0.8.0` / `claude-workflow 1.19.0`:

1. **Enable Sentry AI Monitoring** via `openAIIntegration` (one init-line change; covers per-call spans). Documented in the new `add-observability/openrouter-integration.md` runbook. Requires `@sentry/cloudflare ≥ 10.2.0` (or equivalent in `@sentry/node`, `@sentry/deno`).

2. **Ship a thin `recordLLMResponseMeta` helper** across 3 TS stacks (`ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`) that post-processes the SDK's raw response to capture `x-ratelimit-*` headers + `cache_ratio`. Signature:

   ```typescript
   import type { Envelope } from "./index"; // worker + pages
   // import type { Envelope } from "./index.ts"; // supabase-edge (Deno)
   export type LogEventFn = (envelope: Envelope) => void;
   export function recordLLMResponseMeta(
     logEvent: LogEventFn,
     raw: Response,
     usage: LLMUsage,
     ctx: LLMCallMetaContext,
   ): void;
   ```

   `LogEventFn` is dependency-injected (not imported directly) so the helper remains destination-agnostic per ADR-0014 / §10.6.

3. **Ship a standalone `openrouter-monitor` Worker scaffold** at `add-observability/templates/openrouter-monitor/` that polls `GET /api/v1/key` every 15 min for proactive budget alerting. Wrapped with `withCronMonitor` (ADR-0029) so the monitor has its own heartbeat. Composition chain: `withSentry(env => ({...}), { scheduled: withObservabilityScheduled(withCronMonitor(checkCredit, { monitorSlug })) })` — the FULL chain is mandatory; skipping `withObservabilityScheduled` would no-op the destinations registry. Emits `OpenRouterBudgetCriticalError` at ≥95% used, `openrouter.credit_low` warn at ≥85%, `OpenRouterHealthcheckFailedError` on transport / parse failure. The scaffold ships its own copy of the observability subtree (`src/observability/index.ts` + `middleware.ts` + `cron-monitor.ts` + `destinations/*`) per the per-stack-template-duplication convention.

4. **Document both `openAIIntegration` and `anthropicIntegration`** (generic path) in the runbook with a loud PII gate around `recordInputs:false / recordOutputs:false` defaults. Carve-out: enabling these is allowed for non-user / synthetic / approved-eval traces ONLY, with written `policy.md` approval. The `init/INIT.md` Phase 5.5 §"Optional: LLM observability" consent gate 4 surfaces the choice during scaffolder runs.

## Alternatives Rejected

- **Raw-fetch `wrapLLMCall` helper** (an earlier draft of PROMPT B):
  Would manually instrument `fetch()` against the OpenRouter HTTP API. Rejected: both factiv consumers use the OpenAI SDK; Sentry's `openAIIntegration` already covers per-call telemetry; YAGNI applies. If a future project genuinely needs raw-fetch instrumentation (non-TS / non-Go stack, or stack where the SDK doesn't compile), revisit as a new ADR. The `recordLLMResponseMeta` helper's `LogEventFn`-injected shape is reusable — a future raw-fetch wrapper would emit through the same envelope.

- **Bundled `pricing.json` (model→$/1M-tokens table)**:
  Would let the credit-check Worker compute cost locally. Rejected: pricing tables rot (new models ship weekly); duplicates Sentry AI Monitoring's calc; OpenRouter's `/api/v1/generation?id=` returns per-call cost on demand; `/api/v1/key` returns canonical budget cap. No local table earns its maintenance cost.

- **Anthropic-specific helper ship**:
  Shipping a parallel `recordLLMResponseMeta` for `@anthropic-ai/sdk` Cached Claude consumers. Rejected: no current consumer (fxsa PROMPT C0 hasn't decided yet); Anthropic SDK doesn't expose comparable cache-token headers in its standard response shape; runbook documents the path generically; revisit when a consumer materialises.

- **`add-observability deploy-openrouter-monitor` CLI subcommand** (vs standalone scaffold):
  Would tighten coupling between the scaffolder CLI and a downstream Worker. Rejected: standalone scaffold has a clearer mental model ("a Worker you fork or copy"); doesn't bloat the CLI surface that needs maintenance.

- **Bundled `pricing.json` ops override** (`OPENROUTER_BUDGET_OVERRIDE`):
  Would let ops override the cap reported by `/api/v1/key`. Deferred to v0.9.0 — YAGNI for v0.8.0; the OpenRouter-reported cap is canonical for now.

## Consequences

- **Adoption story**: existing projects adopt via `openrouter-integration.md` (manual copy or via INIT for greenfield); no migration needed. Existing wrapper templates are unchanged — additive only.
- **Helper duplication**: three template copies of `llm-response-meta.ts` (one per TS stack) — matches the per-stack-template-duplication convention (ADR-0014). Cost: ~50 LOC × 3. Benefit: each stack's templates stay self-contained and forkable. The supabase-edge copy uses Deno's `./index.ts` explicit-extension import; worker + pages use the bundler-style `./index`.
- **Monitor scaffold ships its own wrapper subtree**: `src/observability/` is copied verbatim from the `ts-cloudflare-worker` template (~6 files: `index.ts`, `middleware.ts`, `cron-monitor.ts`, `destinations/{index,sentry,axiom}.ts`). The monitor consumes the canonical wrapper without modifying it. If a fork wants to use their own wrapper, they replace the bundled subtree.
- **PII risk surface**: `recordInputs/Outputs:true` would ship prompts/completions to Sentry. The runbook makes this a documented opt-in with a loud `PII GATE` callout; consumer projects (callbot for PHI, cparx for financial PII, etc.) must gate via `policy.md`. Acceptable use is explicitly carved out (synthetic / non-user / approved-eval); non-acceptable use is explicit (real user prompts, PHI, financial PII, chat history).
- **Monitor's own heartbeat**: `withCronMonitor` (ADR-0029) wraps the credit-check Worker so a stalled monitor self-alerts via the existing Sentry monitor for the `openrouter-credit-check` slug. Without this, a silent failure of the monitor itself would mask budget overruns.
- **Sentry SDK minimum bumped**: `openAIIntegration` requires `@sentry/cloudflare 10.2.0+` (per Sentry docs). Projects on `@sentry/cloudflare ^8.x` or `^9.x` need to upgrade before adopting AI Monitoring. The runbook and INIT.md §5.5 detection flag stale SDK versions.
- **Key lifecycle hygiene shipped**: monitor README has a "Security & Secret Lifecycle" subsection documenting `keys:read` scope, per-environment keys, 90-day rotation cadence, accidental-commit prevention, leak-response runbook, and operator-offboarding rotation. This is the README of a Worker that holds the OpenRouter API key — wide enough audience that the lifecycle guidance lives in the README, not in `policy.md`.
- **Forward-compat with raw-fetch**: this ADR explicitly leaves the raw-fetch path open as a future ADR. The `recordLLMResponseMeta` helper's `LogEventFn`-injected shape is reusable: a future raw-fetch wrapper would emit through the same envelope.

## Links

- PROMPT B (operator hand-off, 2026-05-28 revised)
- `.planning/phases/24-openrouter-integration/CONTEXT.md` — locked decisions (D-01 — D-19)
- `.planning/phases/24-openrouter-integration/PLAN.md` — execution plan
- `.planning/phases/24-openrouter-integration/24-REVIEWS.md` — pre-execute multi-AI review (gemini + codex)
- ADR-0014 — Observability architecture
- ADR-0029 — Cron-monitor SDK composition (Guarded Shape A)
- Sentry AI Monitoring (Cloudflare): <https://docs.sentry.io/platforms/javascript/guides/cloudflare/tracing/instrumentation/ai-agents-module/>
- OpenRouter API: <https://openrouter.ai/docs>
- OpenRouter prompt caching: <https://openrouter.ai/docs/features/prompt-caching>
