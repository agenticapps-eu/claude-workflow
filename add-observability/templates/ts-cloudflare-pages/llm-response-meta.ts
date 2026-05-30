// SPDX-License-Identifier: MIT
//
// llm-response-meta.ts — capture OpenRouter response signals that
// Sentry AI Monitoring doesn't surface.
//
// Sentry's openAIIntegration covers per-call telemetry (model/tokens/cost/
// latency). This helper captures the two signals it MISSES:
//   - Rate-limit headroom: x-ratelimit-remaining / x-ratelimit-reset headers.
//   - Cache-read efficacy: cache_ratio computed from usage.prompt_tokens_details.cached_tokens.
//
// Architecture: ADR-0030 — SDK-first OpenRouter integration.
// Runbook:      add-observability/openrouter-integration.md
//
// Call site (consumer):
//
//   const { data, response } = await client.chat.completions
//     .create(req)
//     .withResponse();
//   recordLLMResponseMeta(logEvent, response, data.usage, { model: req.model });
//
// §10.6 destination-independence: logEvent is dependency-injected (not
// imported directly), so this helper has zero coupling to any specific
// destination adapter. The consumer wires their project's logEvent.

import type { Envelope } from "./index";

/**
 * Function shape for emitting structured log envelopes.
 * Matches the signature of `logEvent` exported by lib-observability —
 * declared locally (not imported) for testability + §10.6 portability.
 */
export type LogEventFn = (envelope: Envelope) => void;

/**
 * OpenAI-SDK-compatible usage shape, as returned by both OpenRouter and
 * OpenAI when the OpenAI SDK is used against either endpoint.
 *
 * Verified against:
 *   - https://openrouter.ai/docs/features/prompt-caching
 *   - https://platform.openai.com/docs/guides/prompt-caching
 *
 * All fields are optional — missing fields default to 0 in the emitted attrs.
 */
export interface LLMUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  prompt_tokens_details?: { cached_tokens?: number };
}

/**
 * Per-call context the caller already has at the SDK call site.
 *
 * `service` defaults to "openrouter" — set to "groq" / "together" / etc.
 * when routing through other OpenAI-compatible gateways.
 */
export interface LLMCallMetaContext {
  model: string;
  service?: string;
}

/**
 * Emit an `llm.call_meta` envelope capturing rate-limit headers + cache_ratio.
 *
 * The function is intentionally side-effect-light: it reads from `raw.headers`
 * and from `usage`, computes `cache_ratio`, and emits one envelope. It does
 * NOT log inputs or outputs (PII default: redacted; see runbook §2).
 */
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
      // Explicit divide-by-zero guard (NOT a truthy check on prompt_tokens —
      // 0 is falsy in JS, but the documented contract uses `> 0`).
      cache_ratio: prompt > 0 ? cached / prompt : 0,
    },
  });
}
