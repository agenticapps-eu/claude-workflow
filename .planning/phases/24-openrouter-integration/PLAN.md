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
  - add-observability/templates/openrouter-monitor/tsconfig.json
  - add-observability/templates/openrouter-monitor/README.md
  - add-observability/templates/openrouter-monitor/src/index.ts
  - add-observability/templates/openrouter-monitor/src/check-credit.ts
  - add-observability/templates/openrouter-monitor/src/check-credit.test.ts
  - add-observability/templates/openrouter-monitor/src/observability/index.ts
  - add-observability/templates/openrouter-monitor/src/observability/middleware.ts
  - add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts
  - add-observability/templates/openrouter-monitor/src/observability/destinations/index.ts
  - add-observability/templates/openrouter-monitor/src/observability/destinations/sentry.ts
  - add-observability/templates/openrouter-monitor/src/observability/destinations/axiom.ts
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
    - "Each stack's llm-response-meta.ts: (a) imports Envelope type from the stack's canonical wrapper module per CONTEXT D-04a — worker/pages use `./index` (matches harness `lib-observability.ts → index.ts` rename + matches `meta.yaml target.wrapper_path: src/lib/observability/index.ts` for customer scaffolds); supabase-edge uses `./index.ts` (Deno explicit-extension; supabase source dir already has `index.ts` directly); (b) declares LogEventFn = (envelope: Envelope) => void locally (LogEventFn is NOT exported by lib-observability.ts); (c) exports recordLLMResponseMeta(logEvent, raw, usage, ctx) — dependency-injected logEvent per §10.6 destination-independence."
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
    - "Monitor scaffold uses the FULL wrapper-composition chain: `export default withSentry((env) => ({ dsn: env.SENTRY_DSN, ..., sendDefaultPii: false }), { scheduled: withObservabilityScheduled(withCronMonitor(checkCredit, { monitorSlug })) })`. The composition is mandatory — `withObservabilityScheduled` calls `init()` which configures the destinations registry; without it, `logEvent`/`captureError` no-op silently (codex HIGH-3 fix). The bundled `observability/` subtree (`index.ts` + `middleware.ts` + `cron-monitor.ts` + `destinations/*`) ships with the scaffold per D-09 (codex HIGH-2 fix)."
    - "Monitor handler `check-credit.ts`: (a) GETs https://openrouter.ai/api/v1/key with Authorization: Bearer ${env.OPENROUTER_API_KEY}; (b) parses spend + cap from response body (`data.usage` + `data.limit`; `limit: null` for unlimited keys → used_ratio = 0, pulse only); (c) emits `logEvent({event:'openrouter.credit_pulse', severity:'info', attrs:{used, limit, used_ratio}})` ALWAYS; (d) emits `logEvent({event:'openrouter.credit_low', severity:'warn', attrs:{...}})` when `used_ratio >= WARNING_RATIO` and `< CRITICAL_RATIO` — NOTE the literal `'warn'` not `'warning'` (codex HIGH-4 fix; matches `Severity = 'debug'|'info'|'warn'|'error'|'fatal'` union in lib-observability.ts:27); (e) `captureError(new OpenRouterBudgetCriticalError(used_ratio), {...})` when `used_ratio >= CRITICAL_RATIO`; (f) `captureError(new OpenRouterHealthcheckFailedError(status), {...})` when `/api/v1/key` returns non-2xx, fetch throws (network error → status 0), or `res.json()` throws (malformed body → status -1); (g) on misconfigured thresholds (`WARNING_RATIO >= CRITICAL_RATIO`) emits `logEvent({event:'openrouter.misconfigured_thresholds', severity:'warn', ...})` and falls back to defaults 0.85/0.95."
    - "Monitor env defaults: OPENROUTER_WARNING_RATIO = 0.85 (parsed as float, falls back if missing/NaN); OPENROUTER_CRITICAL_RATIO = 0.95 (same)."
    - "Monitor src/check-credit.test.ts ships 12 fixtures (CONTEXT D-15 revised): (1) under WARNING — pulse only; (2) at WARNING exactly (== 0.85) — pulse + credit_low warn; (3) between WARNING and CRITICAL (0.90) — pulse + credit_low warn; (4) at CRITICAL exactly (== 0.95) — pulse + OpenRouterBudgetCriticalError captured; (5) 401 — HealthcheckFailedError(401); (6) 500 — HealthcheckFailedError(500); (7) 429 rate-limited — HealthcheckFailedError(429); (8) network throw (fetch rejects) — HealthcheckFailedError(0); (9) malformed JSON body — HealthcheckFailedError(-1); (10) limit:null (OpenRouter unlimited-key shape) — used_ratio = 0, pulse only, no warn/critical; (11) inverted thresholds (WARNING_RATIO=0.95, CRITICAL_RATIO=0.85) — misconfig warn + fallback to defaults; (12) invalid env vars (NaN/negative/>1) — fallback to default 0.85. withCronMonitor fail-safe (DSN unset → handler still runs per ADR-0029 Guarded Shape A) is covered by the existing cron-monitor.test.ts contract suite shipped in Phase 23 — NOT re-tested here."
    - "Monitor scaffold package.json pins '@sentry/cloudflare': '^8.0.0' — intentional carve-out from D-17's ^10.2.0 minimum because the monitor itself makes NO LLM calls (Sentry AI Monitoring SDK isn't loaded), so the v10 dependency is unnecessary overhead for this scaffold. The D-17 ^10.2.0 minimum still applies to CONSUMER apps that import the AI Monitoring helpers (openAIIntegration / anthropicIntegration) — Runbook §1 + INIT.md §5.5 detection both lead with the v10 prerequisite for consumer apps. README §1 documents the monitor's v8 carve-out so operators forking into a v10 monorepo know they can bump the pin (the bundled observability/ subtree is forward-compatible). (Stage 2 review I-2 — truth amended post-implementation to match deliberate code decision.)"
    - "Monitor README.md has a 'Security & Secret Lifecycle' subsection (D-18) covering: keys:read scope (T1 mitigation), per-environment keys, 90-day rotation cadence with procedure, accidental-commit prevention (.gitignore + secret-scan hook), leak-response runbook, operator-offboarding rotation."
    - "Runbook §2 (PII GATE) includes the synthetic / non-user data carve-out (D-19): `recordInputs:true`/`recordOutputs:true` are allowed ONLY for non-user/synthetic/approved-eval-dataset traces with written policy.md approval. Concrete acceptable examples listed; non-acceptable examples explicit (real user prompts, PHI, financial PII, chat-history)."
    - "INIT.md §5.5 detection grep broadened per D-13: matches package.json (or workspace package.jsons) for 'openai' or '@anthropic-ai/sdk' AND any of (i) *.ts/*.tsx/*.js/*.mts file containing 'openrouter.ai' (case-insensitive); (ii) wrangler.toml/wrangler.jsonc [env.production.vars] containing OPENROUTER_API_KEY; (iii) .dev.vars/.env.example setting OPENROUTER_API_KEY. Action (a) checks installed @sentry/* version >= 10.2.0 before offering integration insertion."
    - "Monitor README.md leads with 'Use a keys:read-scoped OpenRouter API key' callout (not the generation key) and documents threshold tuning + cron tuning + Sentry alert wiring."
    - "Monitor uses NO second Sentry.init — emits via the project's standard wrapper (logEvent + captureError from the destinations registry). Monitor's handler logic (check-credit.ts) has zero direct @sentry/cloudflare imports; the entry composition (src/index.ts) does import `withSentry` for the standard Cloudflare Sentry SDK setup pattern — this is by design (composition layer ≠ handler logic, per §10.6)."
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
    - path: "add-observability/templates/openrouter-monitor/src/check-credit.ts"
      provides: "Handler logic — separated from composition for testability. Imports logEvent/captureError from ./observability (bundled wrapper)."
      contains: "OpenRouterBudgetCriticalError"
    - path: "add-observability/templates/openrouter-monitor/src/check-credit.test.ts"
      provides: "12 fixture cases per CONTEXT D-15 (under/at-warning/between/at-critical/401/500/429/network/malformed/limit-null/inverted/invalid-env)."
      contains: "OpenRouterBudgetCriticalError"
    - path: "add-observability/templates/openrouter-monitor/src/observability/"
      provides: "Bundled wrapper subtree (copied from ts-cloudflare-worker template). index.ts + middleware.ts + cron-monitor.ts + destinations/*. Required for withObservabilityScheduled to init() the destinations registry (codex HIGH-2 fix)."
      contains: "withObservabilityScheduled"
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

    import type { Envelope } from "./index";

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
    Mirror Task 1.1 verbatim, into `add-observability/templates/ts-cloudflare-pages/`. The helper file is byte-identical to ts-cloudflare-worker — same `./index` import (both stacks materialise `lib-observability.ts` as `index.ts`). The test file is byte-identical.

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
    - add-observability/templates/ts-supabase-edge/index.ts (Envelope shape — Deno-flavoured but Envelope identical; the supabase-edge source dir uses `index.ts` directly, no harness rename per D-04a)
    - add-observability/templates/ts-supabase-edge/index.test.ts (Deno test harness conventions — `Deno.test` if used)
    - Task 1.1 artifacts (helper file shape)
  </read_first>
  <action>
    Per-stack divergence per CONTEXT D-04a:

    **`llm-response-meta.ts` (Deno-style import — supabase-edge uses `./index.ts` not `./index`)**:

    ```typescript
    import type { Envelope } from "./index.ts";  // Deno explicit-extension; matches existing index.test.ts:24 import style
    // rest of the helper body is byte-identical to Task 1.1
    ```

    The supabase-edge source dir already has `index.ts` (no harness rename — source = materialised name). Existing files like `cron-monitor.ts` and `axiom.test.ts` use `npm:@sentry/deno@^8.0.0` / `https://deno.land/std@.../assert/mod.ts` import styles — Deno-native imports.

    **`llm-response-meta.test.ts` (Deno test runner — `Deno.test(...)` not `describe/it`)**:

    Verified via `add-observability/templates/ts-supabase-edge/index.test.ts:14` — the supabase-edge harness uses Deno's built-in test runner (`deno test -A --no-check` in run-template-tests.sh:308), not Vitest. Use the existing Deno test convention from `index.test.ts`:

    ```typescript
    import { assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
    import { recordLLMResponseMeta } from "./llm-response-meta.ts";

    Deno.test("recordLLMResponseMeta — cache hit produces correct cache_ratio", () => {
      const captured: Array<...> = [];
      const logEvent = (env: ...) => captured.push(env);
      const response = new Response("", { headers: { "x-ratelimit-remaining": "42", "x-ratelimit-reset": "1700000000" } });
      recordLLMResponseMeta(logEvent, response, {
        prompt_tokens: 1000,
        completion_tokens: 200,
        prompt_tokens_details: { cached_tokens: 800 },
      }, { model: "anthropic/claude-3.5-sonnet" });
      assertEquals(captured.length, 1);
      assertEquals(captured[0].attrs.cache_ratio, 0.8);
    });

    // ...repeat for the other 6 fixtures from Task 1.1 (7 total per CONTEXT D-15)
    ```

    All 7 fixtures from Task 1.1 are mirrored, just rewritten against the Deno test API + std/assert.

    **Harness wiring** (CONTEXT D-15): supabase-edge harness already uses glob `for f in "$SRC"/*.test.ts` (run-template-tests.sh:472) to copy test files — `llm-response-meta.test.ts` is auto-picked up. But the `.ts` impl needs an explicit substitute_tokens line. RED commit creates only the `.test.ts` (auto-picked-up; deno test fails with "Module not found './llm-response-meta.ts'"). GREEN commit creates the `.ts` impl AND adds `substitute_tokens "$SRC/llm-response-meta.ts" "$OBS_DIR/llm-response-meta.ts"` in the supabase-edge block.

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
  <name>Task 2.2 (Wave 2): openrouter-monitor Worker scaffold + tests (REV 2 — full composition + bundled subtree)</name>
  <files>
    add-observability/templates/openrouter-monitor/package.json
    add-observability/templates/openrouter-monitor/wrangler.toml
    add-observability/templates/openrouter-monitor/tsconfig.json
    add-observability/templates/openrouter-monitor/README.md
    add-observability/templates/openrouter-monitor/src/index.ts
    add-observability/templates/openrouter-monitor/src/check-credit.ts
    add-observability/templates/openrouter-monitor/src/check-credit.test.ts
    add-observability/templates/openrouter-monitor/src/observability/index.ts
    add-observability/templates/openrouter-monitor/src/observability/middleware.ts
    add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts
    add-observability/templates/openrouter-monitor/src/observability/destinations/index.ts
    add-observability/templates/openrouter-monitor/src/observability/destinations/sentry.ts
    add-observability/templates/openrouter-monitor/src/observability/destinations/axiom.ts
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

    **`package.json`** — `@sentry/cloudflare` pinned `^10.2.0` per D-17 (AI Monitoring minimum):
    ```json
    {
      "name": "openrouter-monitor",
      "version": "0.1.0",
      "private": true,
      "type": "module",
      "scripts": {
        "test": "vitest run",
        "deploy": "wrangler deploy",
        "typecheck": "tsc --noEmit"
      },
      "dependencies": {
        "@sentry/cloudflare": "^10.2.0"
      },
      "devDependencies": {
        "@cloudflare/workers-types": "^4.20240909.0",
        "typescript": "^5.4.0",
        "vitest": "^2.0.0",
        "wrangler": "^3.0.0"
      }
    }
    ```

    **`tsconfig.json`** — standard Workers TS config:
    ```json
    {
      "compilerOptions": {
        "target": "ES2022",
        "module": "ESNext",
        "moduleResolution": "bundler",
        "strict": true,
        "skipLibCheck": true,
        "types": ["@cloudflare/workers-types"],
        "lib": ["ES2022"]
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

    **`README.md`** — leads with the security callout, then ships a "Security & Secret Lifecycle" subsection per D-18:

    > ⚠️ **Use a keys:read-scoped OpenRouter API key** — never the generation key. A leaked generation key would burn the org's budget cap within minutes.

    Sections (in order):
    1. **Install** — `npm install` + Sentry SDK 10.2.0+ note (D-17).
    2. **Configure** — secrets table (OPENROUTER_API_KEY, SENTRY_DSN, AXIOM_*) + ratio env vars (OPENROUTER_WARNING_RATIO=0.85, OPENROUTER_CRITICAL_RATIO=0.95) + `wrangler secret put` workflow.
    3. **Deploy** — `wrangler deploy`; verify first run; check `wrangler tail` for `openrouter.credit_pulse` events.
    4. **Tune** — cron frequency (default `*/15 * * * *`); ratio thresholds (project-specific); Sentry alert wiring on `OpenRouterBudgetCriticalError` (issue rule → notification channel); Axiom dashboard wiring on `openrouter.credit_pulse` time-series.
    5. **Security & Secret Lifecycle** (D-18):
       - **Scope**: `keys:read` ONLY. Why: a `keys:read` leak exposes spend metadata; a generation-key leak burns budget cap. Cost of containment = orders of magnitude lower with read-only scope.
       - **Per-environment**: separate `OPENROUTER_API_KEY_DEV` / `OPENROUTER_API_KEY_PROD` (or per-stack `wrangler secret put` bindings on different Worker names). A dev-env leak must NOT expose prod metadata.
       - **Rotation**: 90-day cadence. Procedure: (a) create new `keys:read` key in OpenRouter dashboard; (b) `wrangler secret put OPENROUTER_API_KEY` (new value); (c) verify next scheduled run via `wrangler tail` shows `credit_pulse` with the new key working; (d) revoke old key in OpenRouter dashboard. Downtime: ≤5 min.
       - **Accidental commit prevention**: `.gitignore` covers `.dev.vars`, `*.env`, `*.env.local`; `wrangler.toml` declares secrets only as **comments** (the actual value goes via `wrangler secret put`, never in source). Recommended pre-commit hook: `gitleaks detect` or `trufflehog filesystem .` scanning for OpenRouter key prefix `sk-or-v1-`.
       - **Leak response runbook**: (1) revoke the leaked key in OpenRouter dashboard FIRST (every minute = budget burn risk); (2) rotate per the rotation procedure above; (3) audit `wrangler tail` history for unexpected credit_pulse origins; (4) file a security incident report; (5) post-mortem.
       - **Operator offboarding**: when an operator with deploy access leaves, rotate the key (their shell history, clipboard, 1Password vault may retain the value).
    6. **Fork into a monorepo** — copy the entire `openrouter-monitor/` dir into your repo at a path of your choosing; update `wrangler.toml`'s `name` field; the bundled `src/observability/` subtree is self-contained (no cross-package imports). If you already have an observability wrapper from your main app, replace the bundled subtree with a symlink/import to your existing one.
    7. **Troubleshooting**:
       - No events firing: check `wrangler tail`. If you see nothing on the cron trigger, verify `SENTRY_DSN` is set (without it, `init()` no-ops the registry and `logEvent` silently drops). The healthz of the monitor itself can be checked by inspecting Sentry's monitor for `openrouter-credit-check` slug (Guarded Shape A — ADR-0029).
       - `OpenRouterHealthcheckFailedError` with `status: 0` = network failure (DNS, TLS, OpenRouter outage). With `status: -1` = malformed body (API contract changed; check OpenRouter status page).
       - `OpenRouterBudgetCriticalError` firing but you think it shouldn't: check `wrangler tail` for the latest `credit_pulse` event — `used_ratio` is the source of truth.

    **Bundle the observability subtree FIRST** (codex HIGH-2 fix). Copy these files verbatim from `add-observability/templates/ts-cloudflare-worker/` into the scaffold (no rename — the source-tree `lib-observability.ts` materialises as `observability/index.ts` in the scaffold since the scaffold is the "materialised view" of a customer project):

    - `lib-observability.ts` → `src/observability/index.ts`
    - `middleware.ts` → `src/observability/middleware.ts`
    - `cron-monitor.ts` → `src/observability/cron-monitor.ts`
    - `destinations/index.ts` + `destinations/sentry.ts` + `destinations/axiom.ts` → `src/observability/destinations/*`

    These are the canonical Phase 22/23 files. The monitor does NOT modify them; it CONSUMES them.

    **`src/index.ts`** — entry point with FULL composition chain (codex HIGH-3 fix):

    ```typescript
    // SPDX-License-Identifier: MIT
    //
    // OpenRouter credit-check Worker — entry point.
    // Composition chain (REQUIRED — see ADR-0014, ADR-0029, ADR-0030):
    //
    //   withSentry(env)(withObservabilityScheduled(withCronMonitor(checkCredit, ...)))
    //
    //   withSentry(env)                    — outermost: Sentry.init(env.SENTRY_DSN, ...)
    //   withObservabilityScheduled(...)    — calls init(env, ctx) → configures destinations
    //                                        registry; without this, logEvent/captureError
    //                                        no-op SILENTLY.
    //   withCronMonitor(checkCredit, ...)  — Sentry Crons heartbeat (Guarded Shape A).
    //   checkCredit                        — the handler (see ./check-credit).
    //
    // Architecture: ADR-0030. Runbook: add-observability/openrouter-integration.md

    import { withSentry } from "@sentry/cloudflare";
    import { withObservabilityScheduled } from "./observability/middleware";
    import { withCronMonitor } from "./observability/cron-monitor";
    import { checkCredit } from "./check-credit";

    interface Env {
      OPENROUTER_API_KEY: string;
      OPENROUTER_WARNING_RATIO?: string;
      OPENROUTER_CRITICAL_RATIO?: string;
      SENTRY_DSN: string;
      DEPLOY_ENV?: string;
      SERVICE_NAME?: string;
    }

    export default withSentry(
      (env: Env) => ({
        dsn: env.SENTRY_DSN,
        environment: env.DEPLOY_ENV ?? "production",
        release: env.SERVICE_NAME ?? "openrouter-monitor",
        tracesSampleRate: 0.1,
        sendDefaultPii: false,
        // NOTE: openAIIntegration NOT added here — the monitor makes NO LLM calls.
        // The Sentry.init is solely so logEvent/captureError emit through the
        // registry (which withObservabilityScheduled configures via init()).
      }),
      {
        scheduled: withObservabilityScheduled(
          withCronMonitor(checkCredit, {
            monitorSlug: "openrouter-credit-check",
            handlerName: "scheduled",
          }),
        ),
      },
    );
    ```

    **`src/check-credit.ts`** — handler logic, separated for testability (no `Sentry.init`, no `withSentry`/`withObservabilityScheduled`/`withCronMonitor` — those are wired in `index.ts`):

    ```typescript
    // SPDX-License-Identifier: MIT
    //
    // OpenRouter credit-check handler. Polls /api/v1/key, emits credit_pulse
    // always, credit_low warn at >= WARNING_RATIO, BudgetCriticalError at
    // >= CRITICAL_RATIO, HealthcheckFailedError on transport/parse failure.
    //
    // §10.6 destination-independence: this handler has ZERO direct Sentry
    // SDK calls. All emissions go through logEvent/captureError from the
    // bundled wrapper (which dispatches through the destinations registry).
    //
    // ADR-0030.

    import { logEvent, captureError } from "./observability";

    export class OpenRouterBudgetCriticalError extends Error {
      constructor(public readonly used_ratio: number) {
        super(`OpenRouter budget critical: ${(used_ratio * 100).toFixed(1)}% used`);
        this.name = "OpenRouterBudgetCriticalError";
      }
    }

    export class OpenRouterHealthcheckFailedError extends Error {
      constructor(
        public readonly status: number,
        public readonly cause_kind: "http" | "network" | "parse" = "http",
      ) {
        const kindLabel = cause_kind === "network" ? "network failure" : cause_kind === "parse" ? "malformed body" : `HTTP ${status}`;
        super(`OpenRouter /api/v1/key healthcheck failed: ${kindLabel}`);
        this.name = "OpenRouterHealthcheckFailedError";
      }
    }

    interface Env {
      OPENROUTER_API_KEY: string;
      OPENROUTER_WARNING_RATIO?: string;
      OPENROUTER_CRITICAL_RATIO?: string;
    }

    const DEFAULT_WARNING_RATIO = 0.85;
    const DEFAULT_CRITICAL_RATIO = 0.95;

    function parseRatio(raw: string | undefined, fallback: number): number {
      if (raw === undefined || raw === "") return fallback;
      const n = parseFloat(raw);
      return Number.isFinite(n) && n >= 0 && n <= 1 ? n : fallback;
    }

    export async function checkCredit(
      _controller: ScheduledController,
      env: Env,
      _ctx: ExecutionContext,
    ): Promise<void> {
      let warningRatio = parseRatio(env.OPENROUTER_WARNING_RATIO, DEFAULT_WARNING_RATIO);
      let criticalRatio = parseRatio(env.OPENROUTER_CRITICAL_RATIO, DEFAULT_CRITICAL_RATIO);

      // Misconfig: inverted thresholds → log + fall back to defaults (D-12).
      if (warningRatio >= criticalRatio) {
        logEvent({
          event: "openrouter.misconfigured_thresholds",
          severity: "warn",
          attrs: { warningRatio, criticalRatio, fallback_to: { warning: DEFAULT_WARNING_RATIO, critical: DEFAULT_CRITICAL_RATIO } },
        });
        warningRatio = DEFAULT_WARNING_RATIO;
        criticalRatio = DEFAULT_CRITICAL_RATIO;
      }

      // Fetch — separate try/catch for network errors (D-15 fixture 8).
      let res: Response;
      try {
        res = await fetch("https://openrouter.ai/api/v1/key", {
          headers: { Authorization: `Bearer ${env.OPENROUTER_API_KEY}` },
        });
      } catch (err) {
        captureError(new OpenRouterHealthcheckFailedError(0, "network"), {
          event: "openrouter.healthcheck_failed",
          severity: "error",
          attrs: { status: 0, cause: "network", message: err instanceof Error ? err.message : String(err) },
        });
        return;
      }

      if (!res.ok) {
        // Covers 401 / 429 / 500 / any non-2xx (D-15 fixtures 5/6/7).
        captureError(new OpenRouterHealthcheckFailedError(res.status, "http"), {
          event: "openrouter.healthcheck_failed",
          severity: "error",
          attrs: { status: res.status, cause: "http" },
        });
        return;
      }

      // Parse — separate try/catch for malformed body (D-15 fixture 9).
      let body: { data?: { usage?: number; limit?: number | null } };
      try {
        body = (await res.json()) as { data?: { usage?: number; limit?: number | null } };
      } catch (err) {
        captureError(new OpenRouterHealthcheckFailedError(-1, "parse"), {
          event: "openrouter.healthcheck_failed",
          severity: "error",
          attrs: { status: -1, cause: "parse", message: err instanceof Error ? err.message : String(err) },
        });
        return;
      }

      const used = body.data?.usage ?? 0;
      // limit:null means unlimited per OpenRouter API. Treat as ratio 0 — pulse only (D-15 fixture 10).
      const limit = body.data?.limit ?? 0;
      const used_ratio = limit > 0 ? used / limit : 0;

      // Always emit pulse for the Axiom time-series.
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
        // Severity literal MUST be "warn" not "warning" (matches Severity union).
        logEvent({
          event: "openrouter.credit_low",
          severity: "warn",
          attrs: { used, limit, used_ratio, threshold: warningRatio },
        });
      }
    }
    ```

    **Why split into `index.ts` + `check-credit.ts`?** The composition chain (`withSentry` / `withObservabilityScheduled` / `withCronMonitor`) lives in `index.ts` — it's the production wiring. The handler logic (`checkCredit`) lives in `check-credit.ts` and is unit-tested in isolation by mocking only `./observability`. This keeps the test surface focused on credit-check logic without re-validating the wrapper chain (which has its own contract tests in Phase 22/23).

    **`src/check-credit.test.ts`** (RED first) — 12 fixtures per CONTEXT D-15:

    ```typescript
    import { describe, it, expect, vi, beforeEach } from "vitest";
    import { checkCredit, OpenRouterBudgetCriticalError, OpenRouterHealthcheckFailedError } from "./check-credit";

    // Mock only the bundled wrapper — checkCredit interacts with it via injection.
    vi.mock("./observability", () => ({
      logEvent: vi.fn(),
      captureError: vi.fn(),
    }));
    import { logEvent, captureError } from "./observability";

    beforeEach(() => {
      vi.clearAllMocks();
      // Default fetch mock — overridden per test.
      global.fetch = vi.fn() as never;
    });

    function makeEnv(overrides: Partial<Parameters<typeof checkCredit>[1]> = {}) {
      return {
        OPENROUTER_API_KEY: "sk-or-v1-test",
        ...overrides,
      } as Parameters<typeof checkCredit>[1];
    }

    const noController = {} as ScheduledController;
    const noCtx = {} as ExecutionContext;

    // Fixtures map 1:1 to CONTEXT D-15 fixtures 1-12.

    describe("checkCredit", () => {
      it("(1) under WARNING — pulse only", async () => {
        global.fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ data: { usage: 10, limit: 100 } })));
        await checkCredit(noController, makeEnv(), noCtx);
        expect(logEvent).toHaveBeenCalledTimes(1);
        expect(logEvent).toHaveBeenCalledWith(expect.objectContaining({ event: "openrouter.credit_pulse" }));
        expect(captureError).not.toHaveBeenCalled();
      });

      it("(2) at WARNING exactly (0.85) — pulse + credit_low warn", async () => {
        global.fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ data: { usage: 85, limit: 100 } })));
        await checkCredit(noController, makeEnv(), noCtx);
        expect(logEvent).toHaveBeenCalledTimes(2);
        expect(logEvent).toHaveBeenNthCalledWith(2, expect.objectContaining({ event: "openrouter.credit_low", severity: "warn" }));
        expect(captureError).not.toHaveBeenCalled();
      });

      it("(3) between WARNING and CRITICAL (0.90) — pulse + credit_low warn", async () => { /* ... */ });
      it("(4) at CRITICAL exactly (0.95) — pulse + BudgetCriticalError", async () => {
        global.fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ data: { usage: 95, limit: 100 } })));
        await checkCredit(noController, makeEnv(), noCtx);
        expect(captureError).toHaveBeenCalledWith(
          expect.any(OpenRouterBudgetCriticalError),
          expect.objectContaining({ event: "openrouter.credit_critical" }),
        );
      });
      it("(5) 401 — HealthcheckFailedError(401)", async () => {
        global.fetch = vi.fn().mockResolvedValue(new Response("", { status: 401 }));
        await checkCredit(noController, makeEnv(), noCtx);
        expect(captureError).toHaveBeenCalledWith(
          expect.objectContaining({ status: 401, cause_kind: "http" }),
          expect.any(Object),
        );
      });
      it("(6) 500 — HealthcheckFailedError(500)", async () => { /* same shape, status 500 */ });
      it("(7) 429 — HealthcheckFailedError(429)", async () => { /* same shape, status 429 */ });
      it("(8) network throw — HealthcheckFailedError(0, 'network')", async () => {
        global.fetch = vi.fn().mockRejectedValue(new TypeError("network error"));
        await checkCredit(noController, makeEnv(), noCtx);
        expect(captureError).toHaveBeenCalledWith(
          expect.objectContaining({ status: 0, cause_kind: "network" }),
          expect.any(Object),
        );
      });
      it("(9) malformed JSON — HealthcheckFailedError(-1, 'parse')", async () => {
        global.fetch = vi.fn().mockResolvedValue(new Response("not json"));
        await checkCredit(noController, makeEnv(), noCtx);
        expect(captureError).toHaveBeenCalledWith(
          expect.objectContaining({ status: -1, cause_kind: "parse" }),
          expect.any(Object),
        );
      });
      it("(10) limit:null (unlimited key) — pulse only, no warn/critical", async () => {
        global.fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ data: { usage: 99999, limit: null } })));
        await checkCredit(noController, makeEnv(), noCtx);
        expect(logEvent).toHaveBeenCalledTimes(1);
        expect(logEvent).toHaveBeenCalledWith(expect.objectContaining({ attrs: expect.objectContaining({ used_ratio: 0, limit: 0 }) }));
        expect(captureError).not.toHaveBeenCalled();
      });
      it("(11) inverted thresholds — misconfig warn + fallback to defaults", async () => {
        global.fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ data: { usage: 90, limit: 100 } })));
        await checkCredit(noController, makeEnv({ OPENROUTER_WARNING_RATIO: "0.95", OPENROUTER_CRITICAL_RATIO: "0.85" }), noCtx);
        // First emission is the misconfig warn; second is the pulse; third is credit_low (90/100 = 0.90 >= default 0.85).
        expect(logEvent).toHaveBeenNthCalledWith(1, expect.objectContaining({ event: "openrouter.misconfigured_thresholds", severity: "warn" }));
      });
      it("(12) invalid env vars (NaN/negative/>1) — fallback to default", async () => {
        for (const bad of ["not-a-number", "-1", "1.5", ""]) {
          vi.clearAllMocks();
          global.fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ data: { usage: 85, limit: 100 } })));
          await checkCredit(noController, makeEnv({ OPENROUTER_WARNING_RATIO: bad }), noCtx);
          // 0.85 default kicks in → credit_low warn at 85/100.
          expect(logEvent).toHaveBeenCalledWith(expect.objectContaining({ event: "openrouter.credit_low" }));
        }
      });
    });
    ```

    The full impls of fixtures 3, 6, 7 follow the same shape — listed inline only as `/* ... */` stubs here; the actual test file ships full bodies for all 12.

    RED commit: `test(24): RED — openrouter-monitor handler tests (12 fixtures)`.
    GREEN commit: `feat(24): GREEN — openrouter-monitor scaffold + handler + composition chain`.

    **§10.6 audit at GREEN time**:
    - `grep -E "Sentry\." add-observability/templates/openrouter-monitor/src/check-credit.ts` — must return 0 matches.
    - `grep -E "Sentry\.init" add-observability/templates/openrouter-monitor/src/index.ts` — must return 0 matches (init handled by `withSentry`, not direct call).
    - `grep -E "@sentry/" add-observability/templates/openrouter-monitor/src/check-credit.ts` — must return 0 matches (handler imports nothing from `@sentry/*`).
  </action>
  <verify>
    <automated>
      # File presence
      test -d add-observability/templates/openrouter-monitor &&
      test -f add-observability/templates/openrouter-monitor/package.json &&
      test -f add-observability/templates/openrouter-monitor/wrangler.toml &&
      test -f add-observability/templates/openrouter-monitor/tsconfig.json &&
      test -f add-observability/templates/openrouter-monitor/README.md &&
      test -f add-observability/templates/openrouter-monitor/src/index.ts &&
      test -f add-observability/templates/openrouter-monitor/src/check-credit.ts &&
      test -f add-observability/templates/openrouter-monitor/src/check-credit.test.ts &&
      # Bundled observability subtree (D-09 fix)
      test -f add-observability/templates/openrouter-monitor/src/observability/index.ts &&
      test -f add-observability/templates/openrouter-monitor/src/observability/middleware.ts &&
      test -f add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts &&
      test -f add-observability/templates/openrouter-monitor/src/observability/destinations/index.ts &&
      test -f add-observability/templates/openrouter-monitor/src/observability/destinations/sentry.ts &&
      test -f add-observability/templates/openrouter-monitor/src/observability/destinations/axiom.ts &&
      # Cron schedule
      grep -qE '"\*/15 \* \* \* \*"' add-observability/templates/openrouter-monitor/wrangler.toml &&
      # Full composition chain (D-09 — codex HIGH-3 fix)
      grep -q "withSentry" add-observability/templates/openrouter-monitor/src/index.ts &&
      grep -q "withObservabilityScheduled" add-observability/templates/openrouter-monitor/src/index.ts &&
      grep -q "withCronMonitor" add-observability/templates/openrouter-monitor/src/index.ts &&
      # Error classes + severity literal (D-12 — codex HIGH-4 fix)
      grep -q "OpenRouterBudgetCriticalError" add-observability/templates/openrouter-monitor/src/check-credit.ts &&
      grep -q "OpenRouterHealthcheckFailedError" add-observability/templates/openrouter-monitor/src/check-credit.ts &&
      grep -q 'severity: "warn"' add-observability/templates/openrouter-monitor/src/check-credit.ts &&
      ! grep -q 'severity: "warning"' add-observability/templates/openrouter-monitor/src/check-credit.ts &&
      # Sentry SDK 10.2.0+ pin (D-17)
      grep -q '"@sentry/cloudflare": "\^10\.' add-observability/templates/openrouter-monitor/package.json &&
      # Security & Secret Lifecycle section (D-18)
      grep -q "keys:read" add-observability/templates/openrouter-monitor/README.md &&
      grep -q "Security & Secret Lifecycle" add-observability/templates/openrouter-monitor/README.md &&
      grep -q "rotation" add-observability/templates/openrouter-monitor/README.md &&
      # §10.6 destination-independence audit (D-11)
      ! grep -E "@sentry/" add-observability/templates/openrouter-monitor/src/check-credit.ts &&
      ! grep -E "Sentry\.init\b" add-observability/templates/openrouter-monitor/src/index.ts &&
      # Tests pass
      (cd add-observability/templates/openrouter-monitor && npm install --prefer-offline --no-audit 2>&1 | tail -3 && npm run typecheck && npm test 2>&1 | tail -15) | grep -qE "passed|PASS"
    </automated>
  </verify>
  <done>openrouter-monitor scaffold ships with full composition chain + bundled observability subtree + handler in check-credit.ts + 12 fixtures + README with Security & Secret Lifecycle section + Sentry SDK 10.2.0+ pin; tests pass; typecheck passes; no direct `@sentry/*` imports in check-credit.ts; no Sentry.init call in index.ts (withSentry handles it).</done>
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
4. **§10.6 destination-independence audit** — `grep -rn "@sentry/\|Sentry\." add-observability/templates/openrouter-monitor/src/check-credit.ts` should return 0 matches (handler has no Sentry imports or calls; `index.ts` legitimately uses `withSentry` for the composition chain).
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
