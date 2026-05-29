# OpenRouter Integration

> **Status**: ships with `add-observability 0.8.0` / `claude-workflow 1.19.0`.
> **Architecture**: [ADR-0030 — SDK-first OpenRouter integration](../docs/decisions/0030-openrouter-integration-sdk-first.md).
> **Audience**: project owners with a Cloudflare Workers / Pages / Supabase-Edge backend that calls OpenRouter via the OpenAI SDK and ships their own observability wrapper (per ADR-0014 / §10.6).

This runbook covers the **SDK-first** path: enable Sentry AI Monitoring (one init line), wire the `recordLLMResponseMeta` helper for the signals AI Monitoring doesn't surface, and (optionally) deploy the `openrouter-monitor` Worker for proactive budget alerting.

No raw-fetch wrapper exists — both target consumers (factiv/callbot, factiv/fx-signal-agent) use the OpenAI SDK. If your project doesn't use an SDK, see ADR-0030 §"Alternatives Rejected" for context, then file a feature request.

---

## 1. Enable Sentry AI Monitoring (SDK path)

The OpenAI SDK against OpenRouter (`new OpenAI({ baseURL: 'https://openrouter.ai/api/v1' })`) is auto-instrumentable by Sentry's AI Monitoring. One init-line change gives you per-call spans (model / tokens / cost / latency) in Sentry's AI Monitoring dashboard, with zero per-call-site code changes.

**Prerequisite**: `@sentry/cloudflare ≥ 10.2.0` (or equivalent for `@sentry/node`, `@sentry/deno`). Sentry's OpenAI integration was added in SDK 10.2 — older versions don't ship it. Run `npm ls @sentry/cloudflare` to check your current version; upgrade if needed.

**Cloudflare Workers / Pages**:

```typescript
// src/lib/observability/index.ts (or wherever your Sentry init lives)
import { withSentry } from "@sentry/cloudflare";
import { openAIIntegration } from "@sentry/cloudflare"; // since 10.2.0

export default withSentry(
  (env) => ({
    dsn: env.SENTRY_DSN,
    integrations: [
      openAIIntegration({
        recordInputs: false,   // ⚠️ PII — see §2
        recordOutputs: false,  // ⚠️ PII — see §2
      }),
    ],
    // ... other options
  }),
  { /* handler exports */ },
);
```

**Node.js (`@sentry/node`)**: same `openAIIntegration` name, different import path. Consult `@sentry/node` docs for the version-specific import.

**Supabase Edge (`@sentry/deno`)**: Sentry's Deno SDK exposes the same integration. Consult the `@sentry/deno` docs for the import path on your installed version.

Once enabled, every `client.chat.completions.create()` call is auto-instrumented. Spans appear in Sentry under **Insights → AI Monitoring**. No per-call-site instrumentation needed.

> Verified against Sentry docs: <https://docs.sentry.io/platforms/javascript/guides/cloudflare/tracing/instrumentation/ai-agents-module/> (2026-05-29).

---

## 2. ⚠️ PII GATE — `recordInputs` / `recordOutputs`

> ⚠️ **PII GATE** — `recordInputs:true` and `recordOutputs:true` SHIP PROMPTS AND COMPLETIONS TO SENTRY.

For projects handling sensitive payloads, these flags MUST stay `false`:

- **callbot** (medical, patient data, HIPAA-adjacent) — `false` is non-negotiable.
- **cparx** (financial PII, account / payment metadata) — `false` is non-negotiable.
- **Any product touching real user prompts, customer payloads, PHI, financial PII, or chat history** — `false` by default.

If a project needs to flip either flag, gate the change through the project's `policy.md` (the per-project consent doc) with written approval. The default settings should NOT be quietly flipped during scaffolding or refactor — defaults are intentional.

### ⚠️ Allowed exceptions

`recordInputs:true` / `recordOutputs:true` MAY be enabled for **non-user / synthetic / approved-eval-dataset** traces ONLY, with written `policy.md` approval. Concrete acceptable use:

- **Internal synthetic eval traces** — no real user data, generated from fixed prompt fixtures.
- **Replay testing against canned inputs** — regression testing with project-owned payloads.
- **Approved red-team / probe campaigns** — adversarial inputs the project owns.

**NOT acceptable**:

- Real user prompts, customer payloads, chat history, PHI, financial PII, geolocation, identifying tokens, or anything that survives a "would a user be surprised this is in Sentry?" test.

When you're uncertain, default to `false`. If the policy approval is in flight, default to `false`. Reversing course later costs a rotation + a post-mortem.

---

## 3. Anthropic SDK path (generic)

If your project uses `@anthropic-ai/sdk` directly (or via a Sentry-instrumented Cached-Claude path), the same pattern applies via `anthropicIntegration`:

```typescript
import { anthropicIntegration } from "@sentry/<sdk>";

Sentry.init({
  dsn: env.SENTRY_DSN,
  integrations: [
    anthropicIntegration({
      recordInputs: false,   // ⚠️ same PII gate as §2
      recordOutputs: false,
    }),
  ],
});
```

Same PII defaults (`false`). Same allowed-exceptions carve-out applies (§2). The integration is included in the Sentry SDKs alongside `openAIIntegration` — same minimum SDK version (`10.2.0+`).

This runbook does NOT commit to a specific consumer of `@anthropic-ai/sdk` — fxsa's PROMPT C0 may pick either OpenAI SDK or Anthropic SDK; this section handles either path generically.

---

## 4. Capture the gaps — `recordLLMResponseMeta`

Sentry AI Monitoring's `openAIIntegration` covers per-call telemetry but **does NOT surface**:

1. **Rate-limit headroom** — OpenRouter sends `x-ratelimit-remaining` and `x-ratelimit-reset` response headers. Without capturing them, you don't know how close you are to throttling.
2. **Cache-read efficacy** — `usage.prompt_tokens_details.cached_tokens` reveals how much of the prompt hit OpenRouter's prompt cache. Without this ratio, you can't tell if your caching strategy is working.

`recordLLMResponseMeta` is a thin post-processor that captures both. It ships in the per-stack template:

- `add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts`
- `add-observability/templates/ts-cloudflare-pages/llm-response-meta.ts`
- `add-observability/templates/ts-supabase-edge/llm-response-meta.ts`

Copy the helper into your project's wrapper directory (or scaffold via `/add-observability init` and accept the consent gate 4 prompt — see §5.5 of `init/INIT.md`).

### Call-site wiring

The helper takes `logEvent` by dependency injection (§10.6 destination-independence — the helper doesn't know or care about your destination registry). Wire your project's `logEvent` at call time:

```typescript
import OpenAI from "openai";
import { logEvent } from "./observability";  // or "./observability/index"
import { recordLLMResponseMeta } from "./llm-response-meta";

const client = new OpenAI({
  apiKey: env.OPENROUTER_API_KEY,
  baseURL: "https://openrouter.ai/api/v1",
});

// Use .withResponse() to get the raw Response alongside the parsed body.
const { data, response } = await client.chat.completions
  .create({ model, messages, /* ... */ })
  .withResponse();

// Emits an "llm.call_meta" envelope with rate_remaining, rate_reset,
// cached_tokens, prompt_tokens, completion_tokens, cache_ratio.
recordLLMResponseMeta(logEvent, response, data.usage, { model });

// Use data.choices[0].message.content as you would normally.
return data;
```

The `service` field on the context arg defaults to `"openrouter"`; override (`{ model, service: "groq" }`) if you route through another OpenAI-compatible gateway.

### What it emits

```jsonc
{
  "event": "llm.call_meta",
  "severity": "info",
  "attrs": {
    "model": "anthropic/claude-3.5-sonnet",
    "service": "openrouter",
    "rate_remaining": "42",            // header value (string), null if absent
    "rate_reset":     "1700000000",    // header value (string), null if absent
    "cached_tokens": 800,
    "prompt_tokens": 1000,
    "completion_tokens": 200,
    "cache_ratio": 0.8                  // cached_tokens / prompt_tokens, guards / 0
  }
}
```

Wire your Axiom dashboard against `event:"llm.call_meta"` to chart `cache_ratio` over time and `rate_remaining` as a near-the-cap indicator. See the destinations registry in your wrapper (ADR-0014) for the envelope's downstream routing.

### Field path nuance

The cache field path `usage.prompt_tokens_details.cached_tokens` is the documented shape for OpenAI-SDK-against-OpenRouter responses:

- <https://openrouter.ai/docs/features/prompt-caching>
- <https://platform.openai.com/docs/guides/prompt-caching>

If OpenRouter ever changes this (the field path has been stable since 2024), the helper's `?? 0` default means it silently reports 0 cache hits. Detect drift by cross-checking your Axiom `cache_ratio` against OpenRouter's dashboard.

---

## 5. Proactive budget alerting — the credit-check Worker

Sentry AI Monitoring shows per-call cost. It does NOT show running spend against your OpenRouter org's budget cap. For that, deploy the `openrouter-monitor` Worker scaffold:

📁 [`add-observability/templates/openrouter-monitor/`](./templates/openrouter-monitor/)

A standalone Cloudflare Worker that polls `OpenRouter /api/v1/key` every 15 minutes:

- Emits `openrouter.credit_pulse` (info) **always** — Axiom time-series for the trend chart.
- Emits `openrouter.credit_low` (warn) at **≥85% used** (`OPENROUTER_WARNING_RATIO`, env-overridable).
- Throws `OpenRouterBudgetCriticalError` (captured via `captureError`) at **≥95% used** (`OPENROUTER_CRITICAL_RATIO`). Wire a Sentry alert on this issue type for pager-grade notification.
- Throws `OpenRouterHealthcheckFailedError` on non-2xx, network failure, or malformed response from `/api/v1/key`.

The monitor wraps its scheduled handler with `withCronMonitor` ([ADR-0029](../docs/decisions/0029-cron-monitor-sdk-composition.md) Guarded Shape A), giving it its own Sentry Crons heartbeat. A stalled monitor self-alerts via the `openrouter-credit-check` monitor slug.

Deploy as a separate Worker (the scaffold is standalone and forkable):

```bash
cd add-observability/templates/openrouter-monitor
npm install
wrangler secret put OPENROUTER_API_KEY    # keys:read scope ONLY — see scaffold README
wrangler secret put SENTRY_DSN
wrangler deploy
```

See the scaffold's [`README.md`](./templates/openrouter-monitor/README.md) for the **Security & Secret Lifecycle** section — `keys:read` scope requirement, per-environment keys, 90-day rotation procedure, accidental-commit prevention, leak-response runbook, and operator-offboarding rotation.

---

## Quick adoption checklist

- [ ] `@sentry/<host>` upgraded to `≥ 10.2.0` (verify with `npm ls`)
- [ ] `openAIIntegration({ recordInputs: false, recordOutputs: false })` added to `Sentry.init`
- [ ] `recordInputs` / `recordOutputs` PII gate explicitly confirmed `false` in PR review (§2)
- [ ] `llm-response-meta.ts` copied into the wrapper dir; `recordLLMResponseMeta` wired at every `.create().withResponse()` call site (§4)
- [ ] Axiom dashboard tracks `event:"llm.call_meta"` for `cache_ratio` and `rate_remaining` trends
- [ ] `openrouter-monitor` Worker deployed (separate from main app) with `keys:read`-scoped `OPENROUTER_API_KEY`
- [ ] Sentry alert wired on `OpenRouterBudgetCriticalError` issue type → on-call channel
- [ ] Secret lifecycle policy adopted (per monitor README §"Security & Secret Lifecycle")

---

## Where things live

| Component | Path | Doc |
|---|---|---|
| Architecture decision | `docs/decisions/0030-openrouter-integration-sdk-first.md` | ADR-0030 |
| Wrapper architecture | `docs/decisions/0014-observability-architecture.md` | ADR-0014 |
| Cron monitor wrapper | `docs/decisions/0029-cron-monitor-sdk-composition.md` | ADR-0029 |
| Helper (worker) | `add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts` | this doc §4 |
| Helper (pages) | `add-observability/templates/ts-cloudflare-pages/llm-response-meta.ts` | this doc §4 |
| Helper (supabase-edge) | `add-observability/templates/ts-supabase-edge/llm-response-meta.ts` | this doc §4 (Deno) |
| Monitor scaffold | `add-observability/templates/openrouter-monitor/` | this doc §5 + scaffold README |
| INIT.md surface | `add-observability/init/INIT.md` Phase 5.5 | consent gate 4 |
