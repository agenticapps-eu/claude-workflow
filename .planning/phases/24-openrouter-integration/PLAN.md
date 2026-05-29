---
phase: 24-openrouter-integration
plan: 01
type: execute
wave: multi
depends_on: []
files_modified:
  - docs/decisions/0030-openrouter-integration-sdk-first.md
  - add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts
  - add-observability/templates/ts-cloudflare-worker/llm-response-meta.test.ts
  - add-observability/templates/ts-cloudflare-pages/llm-response-meta.ts
  - add-observability/templates/ts-cloudflare-pages/llm-response-meta.test.ts
  - add-observability/templates/ts-supabase-edge/llm-response-meta.ts
  - add-observability/templates/ts-supabase-edge/llm-response-meta.test.ts
  - add-observability/openrouter-integration.md
  - add-observability/templates/openrouter-monitor/package.json
  - add-observability/templates/openrouter-monitor/wrangler.toml
  - add-observability/templates/openrouter-monitor/README.md
  - add-observability/templates/openrouter-monitor/src/index.ts
  - add-observability/templates/openrouter-monitor/src/index.test.ts
  - add-observability/init/INIT.md
  - add-observability/SKILL.md
  - add-observability/CHANGELOG.md
  - skill/SKILL.md
  - CHANGELOG.md
  - add-observability/templates/run-template-tests.sh
autonomous: true
requirements: []
must_haves:
  truths:
    - "ADR-0030 exists at docs/decisions/0030-openrouter-integration-sdk-first.md with Context / Decision / Alternatives Rejected (including the dropped raw-fetch wrapLLMCall + bundled pricing.json + Anthropic-specific helper) / Consequences sections; links to ADR-0014 and ADR-0029; AUTHORED IN WAVE 0 so executors in Wave 1+ can cite it."
    - "Helper file llm-response-meta.ts ships in 3 TS stacks (ts-cloudflare-worker, ts-cloudflare-pages, ts-supabase-edge). NOT in ts-react-vite (browser must not hold OpenRouter keys) and NOT in go-fly-http (no Go LLM consumer in scope)."
    - "Each stack's llm-response-meta.ts: (a) imports Envelope type from ./lib-observability (NOT from ./index — that path does not exist); (b) declares LogEventFn = (envelope: Envelope) => void locally; (c) exports recordLLMResponseMeta(logEvent, raw, usage, ctx) — dependency-injected logEvent per §10.6 destination-independence."
    - "recordLLMResponseMeta emits envelope { event: 'llm.call_meta', severity: 'info', attrs: { model, service, rate_remaining, rate_reset, cached_tokens, prompt_tokens, completion_tokens, cache_ratio } }."
    - "cache_ratio computation uses an explicit divide-by-zero guard: prompt > 0 ? cached / prompt : 0. (NOT a JS truthy check; truthy works at runtime but explicit guard is the documented contract.)"
    - "service defaults to 'openrouter' when ctx.service is undefined."
    - "rate_remaining and rate_reset come from raw.headers.get('x-ratelimit-remaining') and raw.headers.get('x-ratelimit-reset') verbatim. NULL is an acceptable value (returned when OpenRouter doesn't send the header)."
    - "Each stack ships llm-response-meta.test.ts with ≥5 test cases: (a) cache-hit (cached_tokens > 0 produces correct cache_ratio); (b) cache-miss (cached_tokens = 0 produces cache_ratio = 0); (c) zero prompt_tokens (divide-by-zero safety — cache_ratio = 0, no NaN); (d) missing usage fields (defensive ?? 0 defaults); (e) missing rate-limit headers (raw.headers.get returns null — passed through unchanged)."
    - "Helper tests run under add-observability/templates/run-template-tests.sh harness AFTER each Wave 1 task wires its own substitute_tokens calls (one per stack: ts-cloudflare-worker, ts-cloudflare-pages, ts-supabase-edge). The harness has hardcoded substitute_tokens lines per stack — new test files don't auto-load. RED step adds the .test.ts substitution; GREEN step adds the .ts substitution. Each task therefore touches run-template-tests.sh exactly twice (once per commit). Wave 1 is SERIAL (not parallel-safe) since all three tasks edit the shared harness file."
    - "All 3 helper test commits ship as test(24)/feat(24) RED→GREEN atomic pairs per the workflow skill's TDD discipline. Each RED commit on its own makes the harness fail; the matching GREEN commit makes it pass."
    - "add-observability/openrouter-integration.md exists with 5 sections: (1) Enable Sentry AI Monitoring (SDK path) — openAIIntegration enablement with version-specific import path verified via context7; (2) PII GATE callout (visually loud, > ⚠️ format) — recordInputs:false + recordOutputs:false is the default; flipping requires policy.md consent; (3) Anthropic SDK path — anthropicIntegration enablement documented generically (no consumer commitment); (4) Capture the gaps — wiring recordLLMResponseMeta for rate-limit headroom + cache_ratio; (5) Proactive budget — pointer to the openrouter-monitor scaffold."
    - "Runbook PII callout names callbot (PHI), cparx (financial), and fxsa (market signal — lower risk) as concrete examples + lists policy.md as the consent gate."
    - "Runbook section 1 includes a context7-verified Sentry import path for the current @sentry/cloudflare version. Other Sentry SDK packages (@sentry/node, @sentry/deno) are noted as 'see your SDK's docs — the integration name is the same'."
    - "add-observability/templates/openrouter-monitor/ exists as a standalone scaffold (not a subcommand): package.json (name openrouter-monitor, scripts test/deploy), wrangler.toml (cron '*/15 * * * *', main src/index.ts, kv_namespaces omitted), README.md, src/index.ts, src/index.test.ts."
    - "Monitor src/index.ts: (a) exports default { scheduled }; (b) scheduled handler is wrapped with withCronMonitor; (c) GETs https://openrouter.ai/api/v1/key with Authorization: Bearer ${env.OPENROUTER_API_KEY}; (d) parses spend + cap from response body; (e) emits logEvent({event:'openrouter.credit_pulse', severity:'info', attrs:{used, limit, used_ratio}}) ALWAYS; (f) emits logEvent({event:'openrouter.credit_low', severity:'warning'}) when used_ratio >= WARNING_RATIO and < CRITICAL_RATIO; (g) captureError(new OpenRouterBudgetCriticalError(used_ratio)) when used_ratio >= CRITICAL_RATIO; (h) captureError(new OpenRouterHealthcheckFailedError(status)) when /api/v1/key returns non-2xx."
    - "Monitor env defaults: OPENROUTER_WARNING_RATIO = 0.85 (parsed as float, falls back if missing/NaN); OPENROUTER_CRITICAL_RATIO = 0.95 (same)."
    - "Monitor src/index.test.ts ships ≥6 fixtures: (a) under WARNING — pulse only; (b) at WARNING (== 0.85) — pulse + credit_low warn; (c) at CRITICAL (== 0.95) — pulse + BudgetCriticalError captured; (d) 401 from /api/v1/key — HealthcheckFailedError(401); (e) 500 from /api/v1/key — HealthcheckFailedError(500); (f) withCronMonitor fail-safe — handler still runs when SENTRY_DSN unconfigured."
    - "Monitor README.md leads with 'Use a keys:read-scoped OpenRouter API key' callout (not the generation key) and documents threshold tuning + cron tuning + Sentry alert wiring."
    - "Monitor uses NO second Sentry.init — emits via the project's standard wrapper (logEvent + captureError from the destinations registry). Monitor's src/index.ts has zero direct @sentry/cloudflare imports beyond what withCronMonitor itself transitively pulls."
    - "INIT.md Phase 5 has a new §'Optional: LLM observability' subsection that: (a) runs detection grep (package.json contains 'openai' or '@anthropic-ai/sdk' AND src/ contains 'openrouter.ai'); (b) offers 3 consent-gated actions on match — (i) insert openAIIntegration into existing Sentry init, (ii) copy llm-response-meta.ts, (iii) skip; (c) defaults to (iii) on --yes runs (consent gate 4 matches the existing gate-1/2/3 convention)."
    - "skill/SKILL.md frontmatter version: 1.18.0 → 1.19.0."
    - "add-observability/SKILL.md frontmatter version: 0.7.0 → 0.8.0."
    - "CHANGELOG.md (repo root) has a [1.19.0] entry summarizing: Added (helper × 3 stacks, openrouter-integration.md runbook, openrouter-monitor scaffold, INIT.md §5 §'Optional: LLM observability', ADR-0030); Changed (add-observability bumped 0.7.0→0.8.0); Constraints (SDK-first only — no raw-fetch helper, no migration)."
    - "add-observability/CHANGELOG.md has a 0.8.0 entry covering the per-stack helper + monitor scaffold + INIT.md surface."
    - "Full migration test harness (migrations/run-tests.sh) passes after all changes; full template test harness (add-observability/templates/run-template-tests.sh all) passes after all changes — both the 181-migration baseline and the all-5-stack template baseline remain green."
    - "Net test surface grows by ~21 cases (3 helper test files × ~5 cases + 1 monitor test file × ~6 cases). Existing tests are NOT modified."
    - "PR feat/openrouter-integration-v1.19.0 → main is ready to open with a single squash-merge commit message matching the repo convention 'v1.19.0 feat(add-observability): OpenRouter integration kit (#NN)'."
  artifacts:
    - path: "docs/decisions/0030-openrouter-integration-sdk-first.md"
      provides: "ADR-0030 capturing SDK-first decision; rejected alternatives (raw-fetch wrapLLMCall + bundled pricing.json + Anthropic-specific helper); links to ADR-0014 and ADR-0029."
      contains: "SDK-first"
    - path: "add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts"
      provides: "Helper for ts-cloudflare-worker stack — injected LogEventFn shape."
      contains: "recordLLMResponseMeta"
    - path: "add-observability/templates/ts-cloudflare-worker/llm-response-meta.test.ts"
      provides: "5+ test cases covering cache-hit / cache-miss / div-by-zero / missing fields / missing headers."
      contains: "cache_ratio"
    - path: "add-observability/templates/ts-cloudflare-pages/llm-response-meta.ts"
      provides: "Helper for ts-cloudflare-pages stack (identical shape; per-stack-template-duplication convention)."
      contains: "recordLLMResponseMeta"
    - path: "add-observability/templates/ts-cloudflare-pages/llm-response-meta.test.ts"
      provides: "5+ test cases."
      contains: "cache_ratio"
    - path: "add-observability/templates/ts-supabase-edge/llm-response-meta.ts"
      provides: "Helper for ts-supabase-edge stack (identical shape)."
      contains: "recordLLMResponseMeta"
    - path: "add-observability/templates/ts-supabase-edge/llm-response-meta.test.ts"
      provides: "5+ test cases (Deno harness compat)."
      contains: "cache_ratio"
    - path: "add-observability/openrouter-integration.md"
      provides: "5-section runbook (Sentry init / PII gate / Anthropic path / wiring helper / pointing to monitor)."
      contains: "PII GATE"
    - path: "add-observability/templates/openrouter-monitor/src/index.ts"
      provides: "Scheduled handler — keys-balance check, threshold-gated alerts, withCronMonitor-wrapped."
      contains: "withCronMonitor"
    - path: "add-observability/templates/openrouter-monitor/src/index.test.ts"
      provides: "6+ fixture cases (under/warning/critical/401/500/fail-safe)."
      contains: "OpenRouterBudgetCriticalError"
    - path: "add-observability/templates/openrouter-monitor/README.md"
      provides: "Standalone-scaffold deploy guide + keys:read scope warning + threshold tuning."
      contains: "keys:read"
    - path: "add-observability/init/INIT.md"
      provides: "Phase 5 §'Optional: LLM observability' subsection — consent gate 4."
      contains: "Optional: LLM observability"
    - path: "skill/SKILL.md"
      provides: "Frontmatter version bumped to 1.19.0."
      contains: "1.19.0"
    - path: "add-observability/SKILL.md"
      provides: "Frontmatter version bumped to 0.8.0."
      contains: "0.8.0"
    - path: "CHANGELOG.md"
      provides: "[1.19.0] entry."
      contains: "[1.19.0]"
    - path: "add-observability/CHANGELOG.md"
      provides: "## 0.8.0 entry."
      contains: "## 0.8.0"
---

# Phase 24 — OpenRouter Integration Kit — Execution Plan

> **Branch**: `feat/openrouter-integration-v1.19.0` (cut from `main@7904681` on 2026-05-29).
> **Reads first**: `.planning/phases/24-openrouter-integration/CONTEXT.md` (D-01 — D-16 lock the design),
> `add-observability/templates/ts-cloudflare-worker/lib-observability.ts` (Envelope type + logEvent signature),
> `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts` (withCronMonitor export),
> `docs/decisions/0014-observability-architecture.md` (wrapper contract — destination independence),
> `docs/decisions/0029-cron-monitor-sdk-composition.md` (withCronMonitor Guarded Shape A — monitor's heartbeat).
>
> **Test-baseline pinned**: migrations 181 PASS · templates all-5 stacks PASS at `main@7904681` and at branch HEAD `5f1df85` (CONTEXT commit). Net delta after this phase: +21 cases (templates only — no migration changes).
>
> **Threat-model deltas vs CONTEXT.md**: the `openrouter-monitor` Worker introduces a new outbound HTTP call to `https://openrouter.ai/api/v1/key` carrying a bearer token. STRIDE: Information Disclosure (T1) — leaked key would expose org spend metadata + (if generation-scoped) burn budget. Mitigation: README leads with `keys:read` scope requirement; example wrangler.toml uses `OPENROUTER_API_KEY` as a Worker secret (not in plaintext). Tampering (T2) — non-issue (read-only endpoint). Denial of service (T3) — 15-min cron + single GET ≈ negligible (96 calls/day). Reviewed inline; full STRIDE register in `SECURITY.md` post-execute.

## Wave 0 — ADR-0030 (foundation, no deps)

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 0 — ADR foundation; ships before any code so Wave 1+ tasks cite it -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto">
  <name>Task 0.1 (Wave 0): Author ADR-0030 — OpenRouter integration SDK-first</name>
  <files>docs/decisions/0030-openrouter-integration-sdk-first.md</files>
  <depends_on>none</depends_on>
  <read_first>
    - .planning/phases/24-openrouter-integration/CONTEXT.md §"Resolved decisions" D-03 (SDK-first), D-06 (no pricing.json), D-07 (Anthropic generic)
    - docs/decisions/0014-observability-architecture.md (wrapper contract — cited as "see ADR-0014" in Consequences)
    - docs/decisions/0029-cron-monitor-sdk-composition.md (withCronMonitor used by monitor Worker — cited as "see ADR-0029" in Consequences)
  </read_first>
  <action>
    Author `docs/decisions/0030-openrouter-integration-sdk-first.md` with the following sections:

    **# 0030 — OpenRouter integration: SDK-first**
    **Status**: Accepted  **Date**: 2026-05-29  **Phase**: 24-openrouter-integration

    **## Context**
    AgenticApps projects increasingly use OpenRouter as a unified LLM gateway. Two projects in-flight (factiv/callbot, factiv/fx-signal-agent post-PROMPT-C0) consume it via `new OpenAI({ baseURL: 'https://openrouter.ai/api/v1' })`. Without observability instrumentation, per-call telemetry (model/tokens/cost/latency), rate-limit headroom, cache-read efficacy, and running budget are all invisible.

    **## Decision**
    Ship four SDK-first deliverables under `add-observability 0.8.0`:
    1. Enable **Sentry AI Monitoring** via `openAIIntegration` (one init-line change; covers per-call spans).
    2. Ship a thin **`recordLLMResponseMeta`** helper across 3 TS stacks that post-processes the SDK's raw response to capture rate-limit headers + cache_ratio (signals Sentry AI Monitoring doesn't surface).
    3. Ship a standalone **`openrouter-monitor`** Worker scaffold that polls `GET /api/v1/key` every 15 min for proactive budget alerting, wrapped with `withCronMonitor` (ADR-0029) so the monitor has its own heartbeat.
    4. Document both `openAIIntegration` and `anthropicIntegration` (generic path) in `openrouter-integration.md` with a loud PII gate around `recordInputs:false / recordOutputs:false` defaults.

    The helper is dependency-injected with `LogEventFn` (not direct module import) so it remains destination-agnostic per ADR-0014 / §10.6.

    **## Alternatives Rejected**
    - **Raw-fetch `wrapLLMCall` helper** (an earlier draft of PROMPT B): would manually instrument `fetch()` against the OpenRouter HTTP API. Rejected: both factiv consumers use the OpenAI SDK; Sentry's `openAIIntegration` already covers per-call telemetry; YAGNI applies. If a future project genuinely needs raw-fetch instrumentation (non-TS / non-Go stack, or stack where the SDK doesn't compile), revisit as a new ADR.
    - **Bundled `pricing.json` (model→$/1M-tokens table)**: would let the credit-check Worker compute cost locally. Rejected: pricing tables rot (new models weekly); duplicates Sentry AI Monitoring's calc; OpenRouter's `/api/v1/generation?id=` returns per-call cost on demand; `/api/v1/key` returns canonical budget cap. No local table earns its maintenance cost.
    - **Anthropic-specific helper ship**: shipping a parallel `recordLLMResponseMeta` for `@anthropic-ai/sdk` Cached Claude consumers. Rejected: no current consumer (fxsa PROMPT C0 hasn't decided yet); Anthropic SDK doesn't expose comparable cache-token headers in its standard response shape; runbook documents the path generically; revisit when a consumer materialises.
    - **`add-observability deploy-openrouter-monitor` CLI subcommand** (vs standalone scaffold): would tighten coupling between the scaffolder CLI and a downstream Worker. Rejected: standalone scaffold has a clearer mental model ("a Worker you fork or copy"); doesn't bloat the CLI surface that needs maintenance.

    **## Consequences**
    - **Adoption story**: existing projects adopt via `openrouter-integration.md` (manual or via INIT for greenfield); no migration needed.
    - **Helper duplication**: three template copies of `llm-response-meta.ts` (one per TS stack) — matches the per-stack-template-duplication convention (ADR-0014). Cost: ~50 LOC × 3. Benefit: each stack's templates stay self-contained.
    - **PII risk surface**: `recordInputs/Outputs:true` would ship prompts/completions to Sentry. The runbook makes this a documented opt-in with a loud PII gate; consumer projects (callbot for PHI, cparx for financial PII) must gate via `policy.md`.
    - **Monitor's own heartbeat**: `withCronMonitor` (ADR-0029) wraps the credit-check Worker so a stalled monitor self-alerts. Without this, a silent failure of the monitor itself would mask budget overruns.
    - **Forward-compat with raw-fetch**: this ADR explicitly leaves the raw-fetch path open as a future ADR. The `recordLLMResponseMeta` helper's `LogEventFn`-injected shape is reusable: a future raw-fetch wrapper would emit through the same envelope.

    **## Links**
    - PROMPT B (operator hand-off, 2026-05-28 revised)
    - `.planning/phases/24-openrouter-integration/CONTEXT.md`
    - ADR-0014 — Observability architecture
    - ADR-0029 — Cron-monitor SDK composition (Guarded Shape A)
    - Sentry AI Monitoring docs: https://docs.sentry.io/product/insights/ai/
    - OpenRouter API docs: https://openrouter.ai/docs

    Commit: `docs(24): Wave 0 — ADR-0030 OpenRouter integration SDK-first`.
  </action>
  <verify>
    <automated>
      test -f docs/decisions/0030-openrouter-integration-sdk-first.md &&
      grep -q "^# 0030" docs/decisions/0030-openrouter-integration-sdk-first.md &&
      grep -q "SDK-first" docs/decisions/0030-openrouter-integration-sdk-first.md &&
      grep -q "Alternatives Rejected" docs/decisions/0030-openrouter-integration-sdk-first.md &&
      grep -q "wrapLLMCall" docs/decisions/0030-openrouter-integration-sdk-first.md &&
      grep -q "pricing.json" docs/decisions/0030-openrouter-integration-sdk-first.md &&
      grep -q "Consequences" docs/decisions/0030-openrouter-integration-sdk-first.md &&
      grep -q "ADR-0014" docs/decisions/0030-openrouter-integration-sdk-first.md &&
      grep -q "ADR-0029" docs/decisions/0030-openrouter-integration-sdk-first.md
    </automated>
  </verify>
  <done>ADR-0030 lives at docs/decisions/0030-openrouter-integration-sdk-first.md with all required sections; downstream tasks may cite it.</done>
</task>

## Wave 1 — Helper × 3 TS stacks (SERIAL; TDD)

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 1 — Per-stack helper. Tasks 1.1, 1.2, 1.3 are SERIAL (not parallel) -->
<!-- because all three edit the shared file add-observability/templates/      -->
<!-- run-template-tests.sh to wire substitute_tokens for the new test+impl   -->
<!-- files. Each task contains a RED commit and a GREEN commit per the       -->
<!-- workflow skill's TDD discipline.                                         -->
<!--                                                                          -->
<!-- HARNESS WIRING DISCIPLINE (applies to every Wave 1 task):                -->
<!--   The harness uses `sed "$SRC" > "$DST"` with `set -euo pipefail`, so a  -->
<!--   substitute_tokens line referencing a non-existent source file aborts   -->
<!--   the entire stack run. To stay TDD-honest:                              -->
<!--                                                                          -->
<!--   RED commit  — write llm-response-meta.test.ts ONLY + wire its         -->
<!--                 substitute_tokens line in the harness. Vitest runs but  -->
<!--                 fails with "Cannot find module './llm-response-meta'".  -->
<!--                 This is the verifiable failing-test state.              -->
<!--                                                                          -->
<!--   GREEN commit — write llm-response-meta.ts + wire ITS substitute_tokens-->
<!--                 line in the harness. Vitest passes.                     -->
<!--                                                                          -->
<!--   So each task touches run-template-tests.sh in BOTH commits (once per  -->
<!--   commit, one substitute_tokens line each). The harness edits go in the -->
<!--   stack's own block (around the existing healthz-snippet substitutions).-->
<!--                                                                          -->
<!-- depends_on: Task 0.1 (helpers cite ADR-0030 in JSDoc)                    -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto" tdd="true">
  <name>Task 1.1 (Wave 1): recordLLMResponseMeta — ts-cloudflare-worker</name>
  <files>
    add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts
    add-observability/templates/ts-cloudflare-worker/llm-response-meta.test.ts
  </files>
  <depends_on>Task 0.1</depends_on>
  <read_first>
    - add-observability/templates/ts-cloudflare-worker/lib-observability.ts lines 25-40 (Envelope + Severity types)
    - add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts (test patterns + harness conventions)
    - docs/decisions/0030-openrouter-integration-sdk-first.md (cite in JSDoc)
    - .planning/phases/24-openrouter-integration/CONTEXT.md D-04 (helper signature) + D-05 (cache-token field)
  </read_first>
  <action>
    **Step A (RED)**: Author `llm-response-meta.test.ts` first. It should import `recordLLMResponseMeta` from `./llm-response-meta` (file doesn't exist yet — that's the RED). Test cases:

    1. `cache hit produces correct cache_ratio` — usage `{prompt_tokens: 1000, completion_tokens: 200, prompt_tokens_details: {cached_tokens: 800}}` → envelope.attrs.cache_ratio === 0.8.
    2. `cache miss produces cache_ratio = 0` — `{prompt_tokens: 1000, completion_tokens: 200, prompt_tokens_details: {cached_tokens: 0}}` → cache_ratio === 0.
    3. `divide-by-zero safety` — `{prompt_tokens: 0}` → cache_ratio === 0 (no NaN).
    4. `missing usage fields default to 0` — `{}` → cached_tokens/prompt_tokens/completion_tokens all 0; cache_ratio 0.
    5. `missing rate-limit headers pass through as null` — Response with no `x-ratelimit-*` headers → envelope.attrs.rate_remaining === null, rate_reset === null.
    6. `service defaults to "openrouter"` — ctx without service → attrs.service === "openrouter".
    7. `service override respected` — ctx.service === "groq" → attrs.service === "groq".

    Each test should construct a fake `Response` (via `new Response("", { headers: { ... } })`) and a captured `logEvent` (push envelopes into an array) so assertions inspect the envelope directly.

    Commit RED: `test(24): RED — recordLLMResponseMeta tests (ts-cloudflare-worker)`. Run harness; confirm failure references the missing `./llm-response-meta` module.

    **Step B (GREEN)**: Author `llm-response-meta.ts` with the exact shape from CONTEXT D-04:

    ```typescript
    // SPDX-License-Identifier: MIT
    //
    // recordLLMResponseMeta — capture OpenRouter response signals that
    // Sentry AI Monitoring doesn't surface (rate-limit headroom, cache_ratio).
    // See: docs/decisions/0030-openrouter-integration-sdk-first.md
    //      add-observability/openrouter-integration.md (runbook)
    //
    // Call site (consumer):
    //   const { data, response } = await client.chat.completions.create(req).withResponse();
    //   recordLLMResponseMeta(logEvent, response, data.usage, { model: req.model });

    import type { Envelope } from "./lib-observability";

    export type LogEventFn = (envelope: Envelope) => void;

    export interface LLMUsage {
      prompt_tokens?: number;
      completion_tokens?: number;
      prompt_tokens_details?: { cached_tokens?: number };
    }

    export interface LLMCallMetaContext {
      model: string;
      service?: string;
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

    Run harness; confirm GREEN.

    Commit GREEN: `feat(24): GREEN — recordLLMResponseMeta (ts-cloudflare-worker)`.
  </action>
  <verify>
    <automated>
      test -f add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts &&
      test -f add-observability/templates/ts-cloudflare-worker/llm-response-meta.test.ts &&
      grep -q "recordLLMResponseMeta" add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts &&
      grep -q "import type { Envelope }" add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts &&
      grep -q 'service ?? "openrouter"' add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts &&
      grep -q "prompt > 0 ? cached / prompt : 0" add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts &&
      bash add-observability/templates/run-template-tests.sh ts-cloudflare-worker 2>&1 | grep -q "PASS"
    </automated>
  </verify>
  <done>ts-cloudflare-worker stack ships the helper + tests; 5+ test cases green; harness passes.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 1.2 (Wave 1): recordLLMResponseMeta — ts-cloudflare-pages</name>
  <files>
    add-observability/templates/ts-cloudflare-pages/llm-response-meta.ts
    add-observability/templates/ts-cloudflare-pages/llm-response-meta.test.ts
  </files>
  <depends_on>Task 0.1</depends_on>
  <read_first>
    - add-observability/templates/ts-cloudflare-pages/lib-observability.ts (Envelope shape — should be identical to worker)
    - Task 1.1 artifacts (helper + tests) — file shape is the SAME across stacks (per-stack-template-duplication)
  </read_first>
  <action>
    Mirror Task 1.1 verbatim, into `add-observability/templates/ts-cloudflare-pages/`. The helper file is byte-identical to ts-cloudflare-worker except for the relative import (still `./lib-observability` — both stacks use the same name). The test file is byte-identical.

    RED commit: `test(24): RED — recordLLMResponseMeta tests (ts-cloudflare-pages)`.
    GREEN commit: `feat(24): GREEN — recordLLMResponseMeta (ts-cloudflare-pages)`.
  </action>
  <verify>
    <automated>
      test -f add-observability/templates/ts-cloudflare-pages/llm-response-meta.ts &&
      test -f add-observability/templates/ts-cloudflare-pages/llm-response-meta.test.ts &&
      diff -q add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts add-observability/templates/ts-cloudflare-pages/llm-response-meta.ts &&
      bash add-observability/templates/run-template-tests.sh ts-cloudflare-pages 2>&1 | grep -q "PASS"
    </automated>
  </verify>
  <done>ts-cloudflare-pages stack ships byte-identical helper + tests; harness passes.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 1.3 (Wave 1): recordLLMResponseMeta — ts-supabase-edge</name>
  <files>
    add-observability/templates/ts-supabase-edge/llm-response-meta.ts
    add-observability/templates/ts-supabase-edge/llm-response-meta.test.ts
  </files>
  <depends_on>Task 0.1</depends_on>
  <read_first>
    - add-observability/templates/ts-supabase-edge/lib-observability.ts (Envelope shape — Deno-flavoured but Envelope identical)
    - add-observability/templates/ts-supabase-edge/lib-observability.test.ts (Deno test harness conventions — `Deno.test` if used)
    - Task 1.1 artifacts (helper file shape)
  </read_first>
  <action>
    Mirror Task 1.1 into `add-observability/templates/ts-supabase-edge/`. The helper file is byte-identical to ts-cloudflare-worker. The test file should follow the existing Deno test convention used by `lib-observability.test.ts` in this stack (likely `Deno.test(...)` instead of Vitest's `it(...)` — verify by reading the existing test file first).

    If the Deno harness uses identical Vitest-compatible `it()` (some stacks do via `npm:` imports), keep the test file byte-identical to 1.1's. Otherwise rewrite the test cases against Deno's test API while preserving the 7 cases and assertions.

    RED commit: `test(24): RED — recordLLMResponseMeta tests (ts-supabase-edge)`.
    GREEN commit: `feat(24): GREEN — recordLLMResponseMeta (ts-supabase-edge)`.
  </action>
  <verify>
    <automated>
      test -f add-observability/templates/ts-supabase-edge/llm-response-meta.ts &&
      test -f add-observability/templates/ts-supabase-edge/llm-response-meta.test.ts &&
      grep -q "recordLLMResponseMeta" add-observability/templates/ts-supabase-edge/llm-response-meta.ts &&
      diff -q add-observability/templates/ts-cloudflare-worker/llm-response-meta.ts add-observability/templates/ts-supabase-edge/llm-response-meta.ts &&
      bash add-observability/templates/run-template-tests.sh ts-supabase-edge 2>&1 | grep -q "PASS"
    </automated>
  </verify>
  <done>ts-supabase-edge stack ships the helper + tests; harness passes; helper file matches worker byte-for-byte (test file may diverge if Deno test API differs).</done>
</task>

## Wave 2 — Runbook + Monitor scaffold (parallel-safe)

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 2 — Runbook + Monitor. Tasks 2.1 and 2.2 are parallel-safe          -->
<!-- (no shared files). Both depend on Wave 1 (runbook references the helper, -->
<!-- monitor template can be authored in parallel).                           -->
<!-- depends_on: Wave 1 (Tasks 1.1-1.3) for the helper file path the runbook  -->
<!--             cites; Task 0.1 for the ADR the runbook cites.               -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto">
  <name>Task 2.1 (Wave 2): openrouter-integration.md runbook</name>
  <files>add-observability/openrouter-integration.md</files>
  <depends_on>Tasks 0.1, 1.1, 1.2, 1.3</depends_on>
  <read_first>
    - .planning/phases/24-openrouter-integration/CONTEXT.md §"Specifics" (PII callout shape) + D-07 (Anthropic generic)
    - docs/decisions/0030-openrouter-integration-sdk-first.md (cited inline)
    - Task 1.1's helper file (cited in §4 wiring section)
    - Sentry AI Monitoring docs (context7 verify the exact `openAIIntegration` import path for current @sentry/cloudflare version)
    - OpenRouter API docs (verify usage field path `prompt_tokens_details.cached_tokens`)
  </read_first>
  <action>
    Author `add-observability/openrouter-integration.md` with 5 sections.

    Outline:

    ```markdown
    # OpenRouter Integration

    > Status: ships with `add-observability 0.8.0` / `claude-workflow 1.19.0`.
    > Architecture: ADR-0030 (SDK-first).

    ## 1. Enable Sentry AI Monitoring (SDK path)

    [One-line init change per stack; openAIIntegration with recordInputs/Outputs:false default.
    Include the context7-verified import for @sentry/cloudflare current version.
    Cover @sentry/node + @sentry/deno briefly ("integration name is the same; import path differs per SDK").]

    ## 2. ⚠️ PII GATE — recordInputs/Outputs

    > ⚠️ **PII GATE** — `recordInputs:true` and `recordOutputs:true` SHIP PROMPTS AND COMPLETIONS TO SENTRY.

    [Loud callout. For consumers with sensitive payloads (callbot/PHI, cparx/financial), the defaults
    MUST stay false. Document policy.md as the consent gate. List the concrete consumer classes.]

    ## 3. Anthropic SDK path (generic)

    [If your project uses `@anthropic-ai/sdk`, the same pattern applies via `anthropicIntegration`.
    Same PII defaults. No consumer-specific commitments — fxsa's PROMPT C0 may pick either OpenAI or
    Anthropic SDK; this runbook handles both.]

    ## 4. Capture the gaps — recordLLMResponseMeta

    [Sentry AI Monitoring doesn't surface OpenRouter's x-ratelimit-* headers or cache_ratio.
    Wire `recordLLMResponseMeta` from `add-observability/templates/<stack>/llm-response-meta.ts`
    to capture these. Show the SDK call-site example (with `.withResponse()`).
    Cite ADR-0014 for the destination-independence wiring.]

    ## 5. Proactive budget alerting

    [Pointer to `add-observability/templates/openrouter-monitor/` standalone scaffold.
    Deploy as a separate Cloudflare Worker; cron every 15 min; thresholds at 85% (warn) / 95% (critical).
    Cite ADR-0029 for the withCronMonitor heartbeat.]
    ```

    Each section ≤300 words. The PII callout in §2 must use the `> ⚠️ **PII GATE**` blockquote convention (visually loud). §1's Sentry import path must be context7-verified at authoring time — note the verification date in a footnote.

    Commit: `docs(24): Wave 2 — openrouter-integration.md runbook`.
  </action>
  <verify>
    <automated>
      test -f add-observability/openrouter-integration.md &&
      grep -q "^# OpenRouter Integration" add-observability/openrouter-integration.md &&
      grep -q "## 1. Enable Sentry AI Monitoring" add-observability/openrouter-integration.md &&
      grep -q "PII GATE" add-observability/openrouter-integration.md &&
      grep -q "anthropicIntegration" add-observability/openrouter-integration.md &&
      grep -q "recordLLMResponseMeta" add-observability/openrouter-integration.md &&
      grep -q "openrouter-monitor" add-observability/openrouter-integration.md &&
      grep -q "ADR-0030" add-observability/openrouter-integration.md &&
      grep -q "ADR-0029" add-observability/openrouter-integration.md
    </automated>
  </verify>
  <done>Runbook complete with all 5 sections, loud PII gate, context7-verified Sentry import path.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2.2 (Wave 2): openrouter-monitor Worker scaffold + tests</name>
  <files>
    add-observability/templates/openrouter-monitor/package.json
    add-observability/templates/openrouter-monitor/wrangler.toml
    add-observability/templates/openrouter-monitor/README.md
    add-observability/templates/openrouter-monitor/src/index.ts
    add-observability/templates/openrouter-monitor/src/index.test.ts
  </files>
  <depends_on>Tasks 0.1</depends_on>
  <read_first>
    - add-observability/templates/ts-cloudflare-worker/cron-monitor.ts (withCronMonitor signature)
    - add-observability/templates/ts-cloudflare-worker/lib-observability.ts (logEvent + captureError signatures + Envelope shape)
    - add-observability/templates/ts-cloudflare-worker/middleware.ts (wrapper composition reference)
    - .planning/phases/24-openrouter-integration/CONTEXT.md D-08 (standalone) + D-09 (withCronMonitor) + D-10 (env vars) + D-11 (no second Sentry init) + D-12 (error classes)
    - OpenRouter API docs `GET /api/v1/key` response shape (cached locally during runbook authoring)
  </read_first>
  <action>
    Create `add-observability/templates/openrouter-monitor/` with five files.

    **`package.json`** (minimal):
    ```json
    {
      "name": "openrouter-monitor",
      "version": "0.1.0",
      "private": true,
      "type": "module",
      "scripts": {
        "test": "vitest run",
        "deploy": "wrangler deploy"
      },
      "dependencies": {
        "@sentry/cloudflare": "^9.0.0"
      },
      "devDependencies": {
        "@cloudflare/workers-types": "^4.20240909.0",
        "vitest": "^2.0.0",
        "wrangler": "^3.0.0"
      }
    }
    ```

    **`wrangler.toml`**:
    ```toml
    name = "openrouter-monitor"
    main = "src/index.ts"
    compatibility_date = "2026-05-29"

    [triggers]
    crons = ["*/15 * * * *"]

    # Secrets to set via `wrangler secret put`:
    #   OPENROUTER_API_KEY           — read-only key, scope: keys:read ONLY
    #   SENTRY_DSN                   — for openAIIntegration + captureError dispatch
    #   AXIOM_TOKEN, AXIOM_DATASET   — optional logEvent destination
    #
    # Optional env vars (set in [vars] block or via secret put):
    #   OPENROUTER_WARNING_RATIO     — defaults to 0.85
    #   OPENROUTER_CRITICAL_RATIO    — defaults to 0.95
    ```

    **`README.md`**:
    Leads with:

    > ⚠️ **Use a keys:read-scoped OpenRouter API key** — never the generation key. A leaked generation key would burn the org's budget cap.

    Sections: Install · Configure (secrets table + ratio env vars) · Deploy (`wrangler deploy`) · Tune (cron frequency · ratio thresholds · Sentry alert wiring on `OpenRouterBudgetCriticalError`) · Fork into a monorepo · Troubleshooting (failed healthcheck = `OpenRouterHealthcheckFailedError(status)`).

    **`src/index.ts`** (RED first — write `src/index.test.ts` before this):

    ```typescript
    // SPDX-License-Identifier: MIT
    //
    // OpenRouter credit-check Worker — polls /api/v1/key every 15 min,
    // emits credit_pulse always, credit_low warn at >= WARNING_RATIO,
    // captureError(OpenRouterBudgetCriticalError) at >= CRITICAL_RATIO.
    // Wrapped with withCronMonitor (ADR-0029) — monitor has its own heartbeat.
    //
    // Architecture: ADR-0030.
    // Runbook: add-observability/openrouter-integration.md

    import { withCronMonitor } from "./cron-monitor";
    import { logEvent, captureError } from "./lib-observability";

    export class OpenRouterBudgetCriticalError extends Error {
      constructor(public readonly used_ratio: number) {
        super(`OpenRouter budget critical: ${(used_ratio * 100).toFixed(1)}% used`);
        this.name = "OpenRouterBudgetCriticalError";
      }
    }

    export class OpenRouterHealthcheckFailedError extends Error {
      constructor(public readonly status: number) {
        super(`OpenRouter /api/v1/key returned ${status}`);
        this.name = "OpenRouterHealthcheckFailedError";
      }
    }

    interface Env {
      OPENROUTER_API_KEY: string;
      OPENROUTER_WARNING_RATIO?: string;
      OPENROUTER_CRITICAL_RATIO?: string;
      SENTRY_DSN?: string;
    }

    const DEFAULT_WARNING_RATIO = 0.85;
    const DEFAULT_CRITICAL_RATIO = 0.95;

    function parseRatio(raw: string | undefined, fallback: number): number {
      if (!raw) return fallback;
      const n = parseFloat(raw);
      return Number.isFinite(n) && n >= 0 && n <= 1 ? n : fallback;
    }

    async function checkCredit(_controller: ScheduledController, env: Env, _ctx: ExecutionContext): Promise<void> {
      const warningRatio = parseRatio(env.OPENROUTER_WARNING_RATIO, DEFAULT_WARNING_RATIO);
      const criticalRatio = parseRatio(env.OPENROUTER_CRITICAL_RATIO, DEFAULT_CRITICAL_RATIO);

      const res = await fetch("https://openrouter.ai/api/v1/key", {
        headers: { Authorization: `Bearer ${env.OPENROUTER_API_KEY}` },
      });
      if (!res.ok) {
        captureError(new OpenRouterHealthcheckFailedError(res.status), {
          event: "openrouter.healthcheck_failed",
          severity: "error",
          attrs: { status: res.status },
        });
        return;
      }
      const body = (await res.json()) as { data?: { usage?: number; limit?: number | null } };
      const used = body.data?.usage ?? 0;
      const limit = body.data?.limit ?? 0;
      const used_ratio = limit > 0 ? used / limit : 0;

      logEvent({
        event: "openrouter.credit_pulse",
        severity: "info",
        attrs: { used, limit, used_ratio },
      });

      if (used_ratio >= criticalRatio) {
        captureError(new OpenRouterBudgetCriticalError(used_ratio), {
          event: "openrouter.credit_critical",
          severity: "error",
          attrs: { used, limit, used_ratio, threshold: criticalRatio },
        });
      } else if (used_ratio >= warningRatio) {
        logEvent({
          event: "openrouter.credit_low",
          severity: "warning",
          attrs: { used, limit, used_ratio, threshold: warningRatio },
        });
      }
    }

    export default {
      scheduled: withCronMonitor(checkCredit, { monitorSlug: "openrouter-credit-check" }),
    };
    ```

    **Note on imports**: `withCronMonitor` and the observability primitives import from local files. The scaffold ships its own copies of `cron-monitor.ts` and `lib-observability.ts` (carry from `ts-cloudflare-worker/` template — standalone scaffold means no cross-template path dependencies). Initial scaffold materialisation copies these two files in.

    Alternative: scaffold references the worker template's files via relative path `../ts-cloudflare-worker/cron-monitor`. Reject — breaks "standalone scaffold" mental model and forces a working monorepo on the consumer.

    **`src/index.test.ts`** (RED first):

    Fixtures (use vitest's `fetch` mock):

    1. `under WARNING` — fixture body `{data: {usage: 10, limit: 100}}` → cap loop captures logEvent calls; assert ONE call with `event:"openrouter.credit_pulse"`. No warning, no error.
    2. `at WARNING (exactly 0.85)` — `{data: {usage: 85, limit: 100}}` → pulse + `credit_low warn`.
    3. `between WARNING and CRITICAL (0.90)` — `{data: {usage: 90, limit: 100}}` → pulse + `credit_low warn`.
    4. `at CRITICAL (exactly 0.95)` — `{data: {usage: 95, limit: 100}}` → pulse + `captureError(OpenRouterBudgetCriticalError)`.
    5. `401 unauthorized` — fetch returns 401 → `captureError(OpenRouterHealthcheckFailedError)` with status 401, no other emissions.
    6. `500 upstream error` — fetch returns 500 → `captureError(OpenRouterHealthcheckFailedError(500))`.
    7. `withCronMonitor fail-safe` — when `SENTRY_DSN` is unset, handler still runs (cron must always execute per ADR-0029 Guarded Shape A).
    8. `env.OPENROUTER_WARNING_RATIO override` — set to "0.70" → trigger warn at 0.75 spend.
    9. `env.OPENROUTER_WARNING_RATIO invalid (NaN, negative, >1)` → falls back to default 0.85.

    Mock `logEvent` and `captureError` via vi.mock of the local `./lib-observability` path.

    RED commit: `test(24): RED — openrouter-monitor handler tests`.
    GREEN commit: `feat(24): GREEN — openrouter-monitor scaffold + handler`.

    Verify the monitor doesn't ship a second `Sentry.init` call — `grep -L "Sentry.init" src/index.ts` should match (the init is handled by withCronMonitor + the observability wrapper transitively).
  </action>
  <verify>
    <automated>
      test -d add-observability/templates/openrouter-monitor &&
      test -f add-observability/templates/openrouter-monitor/package.json &&
      test -f add-observability/templates/openrouter-monitor/wrangler.toml &&
      test -f add-observability/templates/openrouter-monitor/README.md &&
      test -f add-observability/templates/openrouter-monitor/src/index.ts &&
      test -f add-observability/templates/openrouter-monitor/src/index.test.ts &&
      grep -q '"\*/15 \* \* \* \*"' add-observability/templates/openrouter-monitor/wrangler.toml &&
      grep -q "withCronMonitor" add-observability/templates/openrouter-monitor/src/index.ts &&
      grep -q "OpenRouterBudgetCriticalError" add-observability/templates/openrouter-monitor/src/index.ts &&
      grep -q "OpenRouterHealthcheckFailedError" add-observability/templates/openrouter-monitor/src/index.ts &&
      grep -q "keys:read" add-observability/templates/openrouter-monitor/README.md &&
      ! grep -q "Sentry.init" add-observability/templates/openrouter-monitor/src/index.ts &&
      (cd add-observability/templates/openrouter-monitor && npm install --prefer-offline --no-audit 2>&1 | tail -3 && npm test 2>&1 | tail -10) | grep -qE "passed|PASS"
    </automated>
  </verify>
  <done>openrouter-monitor scaffold ships with handler + tests + README + wrangler.toml + package.json; tests pass; no second Sentry.init; withCronMonitor wraps the scheduled export.</done>
</task>

## Wave 3 — INIT.md + version bumps + CHANGELOG (final)

<!-- ════════════════════════════════════════════════════════════════════════ -->
<!-- WAVE 3 — Finalisation. INIT.md detection + consent gate 4 + version     -->
<!-- bumps + CHANGELOG. Depends on all prior waves.                           -->
<!-- ════════════════════════════════════════════════════════════════════════ -->

<task type="auto">
  <name>Task 3.1 (Wave 3): INIT.md §5 §"Optional: LLM observability" + version bumps + CHANGELOG</name>
  <files>
    add-observability/init/INIT.md
    add-observability/SKILL.md
    add-observability/CHANGELOG.md
    skill/SKILL.md
    CHANGELOG.md
  </files>
  <depends_on>Tasks 0.1, 1.1, 1.2, 1.3, 2.1, 2.2</depends_on>
  <read_first>
    - add-observability/init/INIT.md Phase 5 §"Optional: LLM observability" anchor location (existing structure for consent gates 1-3)
    - .planning/phases/24-openrouter-integration/CONTEXT.md D-13 (INIT.md surface) + D-01 (version bumps)
    - add-observability/CHANGELOG.md (style of existing entries — 0.7.0 entry from Phase 23 for matching tone)
    - CHANGELOG.md repo root (style of existing [1.18.0] entry for matching tone)
  </read_first>
  <action>
    **Edit add-observability/init/INIT.md** — add a new subsection §"Optional: LLM observability" under Phase 5, after the existing per-stack subsections.

    Content:

    ```markdown
    ### Phase 5.5 — Optional: LLM observability (consent gate 4)

    **Detection grep**:
    ```bash
    if grep -qE '"(openai|@anthropic-ai/sdk)"' package.json 2>/dev/null && \
       grep -rq 'openrouter\.ai' src/ 2>/dev/null; then
       trigger=true
    fi
    ```

    **If matched, offer three actions (consent gate 4):**

    (a) **Insert AI Monitoring integration** — add `openAIIntegration({recordInputs:false, recordOutputs:false})` (or `anthropicIntegration` if the project uses `@anthropic-ai/sdk`) into the existing `Sentry.init` integrations array.

    (b) **Copy `llm-response-meta.ts`** — drop the per-stack helper into the project's wrapper directory.

    (c) **Skip** — already configured / not needed / will adopt later via runbook.

    **Default on `--yes`**: (c). The runbook (`openrouter-integration.md`) is the canonical manual-adoption path.

    See ADR-0030 for the SDK-first architecture rationale.
    ```

    **Bump `add-observability/SKILL.md` frontmatter**:

    ```yaml
    version: 0.8.0
    ```

    (Currently 0.7.0; locked in CONTEXT D-01.)

    **Bump `skill/SKILL.md` frontmatter**:

    ```yaml
    version: 1.19.0
    ```

    (Currently 1.18.0.)

    **Append to `add-observability/CHANGELOG.md`** at top (above the 0.7.0 entry):

    ```markdown
    ## 0.8.0 — 2026-05-29

    ### Added
    - `recordLLMResponseMeta` helper across ts-cloudflare-worker, ts-cloudflare-pages, ts-supabase-edge (Phase 24, ADR-0030). Post-processes the OpenAI SDK's raw response to capture x-ratelimit-* headers + cache_ratio — signals Sentry AI Monitoring doesn't surface. Skipped for ts-react-vite (browser stack) and go-fly-http (no Go LLM consumer in scope).
    - `templates/openrouter-monitor/` standalone Worker scaffold. Polls OpenRouter `/api/v1/key` every 15 min; emits `openrouter.credit_pulse` always, `openrouter.credit_low` warn at >=85%, `OpenRouterBudgetCriticalError` at >=95%. Wrapped with `withCronMonitor` (ADR-0029) so the monitor has its own heartbeat. README leads with `keys:read`-scope warning.
    - `openrouter-integration.md` runbook — 5 sections (Sentry AI Monitoring init, PII gate, Anthropic generic path, helper wiring, monitor pointer).
    - `init/INIT.md` Phase 5.5 §"Optional: LLM observability" consent gate 4 — detection grep + 3 actions (insert integration, copy helper, skip). Defaults to skip on `--yes`.

    ### Changed
    - Skill version 0.7.0 → 0.8.0 minor (additive — new helper across 3 stacks + new scaffold + new INIT surface; no removal, no migration).
    ```

    **Append to repo-root `CHANGELOG.md`** at top (above the existing [1.18.0] entry):

    ```markdown
    ## [1.19.0] — 2026-05-29

    ### Added
    - **OpenRouter integration kit** (Phase 24, ADR-0030). Four deliverables ship together: per-stack `recordLLMResponseMeta` helper (3 TS stacks), `openrouter-integration.md` runbook with loud PII gate, standalone `openrouter-monitor` Worker scaffold (forkable), and `init/INIT.md` Phase 5.5 §"Optional: LLM observability" consent gate 4.
    - `docs/decisions/0030-openrouter-integration-sdk-first.md` — ADR records the SDK-first architecture (rejected: raw-fetch `wrapLLMCall`, bundled `pricing.json`, Anthropic-specific helper, CLI subcommand for the monitor).

    ### Changed
    - `add-observability` bumped 0.7.0 → 0.8.0 (additive).
    - `skill/SKILL.md` version 1.18.0 → 1.19.0 (no migration — purely additive across the skill).

    ### Notes
    - SDK-first only — no raw-fetch helper ships. Both factiv consumers (callbot, fxsa post-PROMPT-C0) use the OpenAI SDK; Sentry AI Monitoring's `openAIIntegration` covers per-call telemetry. If a future project needs raw-fetch instrumentation, that's a new ADR.
    - Existing projects adopt via the runbook (manual or via INIT for greenfield).
    ```

    Commit: `feat(24): Wave 3 — INIT.md §5.5 + skill version bumps + CHANGELOG entries`.
  </action>
  <verify>
    <automated>
      grep -q "Optional: LLM observability" add-observability/init/INIT.md &&
      grep -q "consent gate 4" add-observability/init/INIT.md &&
      grep -q "^version: 0.8.0" add-observability/SKILL.md &&
      grep -q "^version: 1.19.0" skill/SKILL.md &&
      grep -q "^## 0.8.0" add-observability/CHANGELOG.md &&
      grep -q "^## \[1.19.0\]" CHANGELOG.md
    </automated>
  </verify>
  <done>INIT.md surface in place; both SKILL.md frontmatter blocks bumped; both CHANGELOGs have the new entries.</done>
</task>

## Verification (post-execute, before PR)

After Wave 3 completes:

1. **Full migration test harness** — `bash migrations/run-tests.sh` — expected 181 PASS unchanged.
2. **Full template test harness** — `bash add-observability/templates/run-template-tests.sh all` — expected all 5 stacks PASS; net new test count ≈ +15 (3 helper test files × ~5 cases each; the monitor scaffold's tests run via its own `npm test` via the Wave 2.2 task verify clause, not the template harness — note this in VERIFICATION.md so the auditor doesn't miss them).
3. **gsd-tools.cjs detect-changes** — confirm only intended symbols touched. Expected: 4 new files in `add-observability/templates/openrouter-monitor/src/`, 3 pairs of helper/test files (one per TS stack), 1 new ADR, 1 runbook, 1 INIT.md edit, 2 SKILL.md frontmatter edits, 2 CHANGELOG appends.
4. **§10.6 destination-independence audit** — `grep -rn "Sentry\." add-observability/templates/openrouter-monitor/src/index.ts` should return 0 matches (no direct SDK calls in handler logic).
5. **PII default verification** — `grep -n "recordInputs\|recordOutputs" add-observability/openrouter-integration.md` should show `:false` in every occurrence inside the runbook's own examples.

## Acceptance criteria (PR-ready)

- [ ] All 5 waves complete; 11 atomic commits on `feat/openrouter-integration-v1.19.0`:
  - 0.1 — ADR-0030 (1 commit)
  - 1.1 — worker helper RED + GREEN (2 commits)
  - 1.2 — pages helper RED + GREEN (2 commits)
  - 1.3 — supabase-edge helper RED + GREEN (2 commits)
  - 2.1 — runbook (1 commit)
  - 2.2 — monitor RED + GREEN (2 commits)
  - 3.1 — INIT.md + bumps + CHANGELOGs (1 commit)
- [ ] `migrations/run-tests.sh` → 181 PASS
- [ ] `add-observability/templates/run-template-tests.sh all` → all 5 stacks PASS
- [ ] `add-observability/templates/openrouter-monitor && npm test` → fixtures PASS
- [ ] `git diff main..feat/openrouter-integration-v1.19.0 -- '*.ts' '*.json' '*.toml'` shows only the additions enumerated in `files_modified` (no incidental drift)
- [ ] CHANGELOG entries at repo root + add-observability mention OpenRouter, helper × 3 stacks, monitor scaffold, INIT.md surface, ADR-0030
- [ ] ADR-0030 cited from runbook, helper JSDoc, monitor JSDoc, INIT.md §5.5

## Threat-model summary (for SECURITY.md post-execute)

The §"Threat-model deltas vs CONTEXT.md" section in the frontmatter is binding. Post-execute audit (gstack `/cso`) will produce `SECURITY.md` with the full STRIDE register.

Primary surface: the `openrouter-monitor` Worker. Threats: T1 (Information Disclosure — leaked OPENROUTER_API_KEY); T2 (Tampering — non-issue for read-only endpoint); T3 (DoS — negligible cron volume); T4 (Repudiation — N/A, internal monitoring); T5 (Spoofing — fetch is to canonical OpenRouter domain over HTTPS); T6 (Privilege escalation — N/A, no auth surface).

Mitigations: README leads with `keys:read` scope requirement; example wrangler.toml documents secret-binding pattern; no plaintext API key in any committed file; `OPENROUTER_API_KEY` is declared as a secret in wrangler.toml comments.

## Out-of-scope / follow-ups

(All carried forward to CONTEXT.md `<deferred>` — listed here for executor reference.)

- WR-01 / WR-02 / WR-03 from Phase 23 — advisory items.
- A-01 / A-02 from Phase 23 — security advisories.
- Go stack helper — no Go LLM consumer in scope.
- react-vite helper — browser must not hold OpenRouter keys.
- `OPENROUTER_BUDGET_OVERRIDE` ops override — v0.9.0 candidate.
- ROADMAP.md / STATE.md retroactive bootstrap — separate phase.
- GH Actions CI — independent of this PR.
