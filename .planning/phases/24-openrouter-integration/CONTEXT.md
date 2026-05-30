# Phase 24 — OpenRouter integration kit (claude-workflow 1.19.0)

> **STATUS: RESOLVED (rev 2) — ready for `/gsd-plan-phase 24`.**
> Rev 1 locked on 2026-05-29 via `--auto` discuss-phase.
> Rev 2 (2026-05-29) incorporates gemini + codex multi-AI plan review
> findings (see `24-REVIEWS.md`). 4 HIGH issues caught by codex + 5 MEDIUM
> agreed by both reviewers folded into the decisions below.

**Branch**: `feat/openrouter-integration-v1.19.0` (cut from `main@7904681`, 2026-05-29).
**Spec target**: `agenticapps-workflow-core@v0.4.0` — no spec change. §10.6 destination-independence covers all four deliverables.
**Version bump (locked per D-01)**: `claude-workflow 1.18.0 → 1.19.0` minor; `add-observability 0.7.0 → 0.8.0` minor. **No migration** — purely additive. Existing projects adopt via the runbook.
**Date opened**: 2026-05-29
**Date resolved (rev 1)**: 2026-05-29
**Date resolved (rev 2 — review fold-in)**: 2026-05-29
**Hand-off source**: PROMPT B (operator-supplied 2026-05-28; revised 2026-05-28 to drop the raw-fetch `wrapLLMCall` helper as YAGNI).
**Review record**: `24-REVIEWS.md` (gemini + codex, claude self-excluded, coderabbit/opencode not installed).

## Sequencing note — prompt numbering vs reality

PROMPT B was authored before PROMPT A (Phase 23) merged. Resolution:

| Item | Prompt said | Reality at 7904681 | Locked |
|------|-------------|--------------------|--------|
| Phase number | 23 | 23 = `observability-followups` (merged) | **24** |
| ADR number | 0029 | 0029 = `cron-monitor SDK composition` (merged) | **0030** |
| `add-observability` version | 0.6.0 → 0.7.0 | already at 0.7.0 | **0.7.0 → 0.8.0** |
| `claude-workflow` version | 1.18.0 → 1.19.0 | at 1.18.0 | **1.18.0 → 1.19.0** ✓ |

Prompt's `Read first` list referenced `add-observability/templates/ts-cloudflare-worker/observability.ts` — actual filename is `lib-observability.ts` in worker + pages source dirs; in supabase-edge source dir the file is named `index.ts` (different source-naming convention). Correction recorded in D-04 / D-04a.

<decisions>
## Resolved decisions (D-01 — D-18)

> All decisions auto-resolved during `--auto` discuss-phase 2026-05-29
> (PROMPT B's 3 explicit open questions + 6 brainstorming-gap decisions
> + 3 numbering reconciliations), then revised against the multi-AI
> review findings in `24-REVIEWS.md`. See `24-DISCUSSION-LOG.md` for
> the per-decision option matrix.

**D-01 — Version bumps.** `claude-workflow 1.18.0 → 1.19.0` minor; `add-observability 0.7.0 → 0.8.0` minor; no migration; CHANGELOG `[1.19.0]` entry; bump `skill/SKILL.md` and `add-observability/SKILL.md` frontmatter `version:` fields. Existing projects adopt the new helper + monitor via the runbook (manual copy or via INIT for greenfield). *(OQ-1 → bumps; aligned with handoff's "versioning tracks migrations" invariant — these are template-side additions, not migration-engine fixes, so a minor bump is honest.)*

**D-02 — Phase scope = four deliverables, batched into one phase / one PR.**
1. `recordLLMResponseMeta` helper across 3 TS stacks (worker, pages, supabase-edge).
2. `add-observability/openrouter-integration.md` runbook.
3. `add-observability/templates/openrouter-monitor/` standalone Worker scaffold.
4. `docs/decisions/0030-openrouter-integration-sdk-first.md` ADR + `init/INIT.md` Phase 5 §"Optional: LLM observability" + CHANGELOG + version bumps.

**D-03 — SDK-first only. No raw-fetch `wrapLLMCall`.** Per PROMPT B's revision. Both factiv consumers use the OpenAI SDK; Sentry AI Monitoring's `openAIIntegration` covers per-call telemetry. Gaps (rate-limit headroom, cache_ratio, running budget) covered by D-04 (helper) + D-09 (monitor Worker). No raw-fetch consumer exists; YAGNI. Future raw-fetch consumer = new ADR.

**D-04 — Helper signature: dependency-injected `LogEventFn` (testability + §10.6).** Final shape:

```ts
// add-observability/templates/<stack>/llm-response-meta.ts
import type { Envelope } from "./index";     // worker + pages (bundler resolution)
// import type { Envelope } from "./index.ts"; // supabase-edge (Deno explicit-extension)

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
1. Import the **type** `Envelope` (not the non-existent `LogEventFn`) from the stack's canonical wrapper module. PROMPT B's `./index` was correct for worker + pages; supabase-edge needs `./index.ts` (Deno style). See D-04a for the per-stack matrix.
2. Declare `LogEventFn` locally as `(envelope: Envelope) => void` rather than importing it — `LogEventFn` is NOT exported by the wrapper module.
3. Guard `cache_ratio` against divide-by-zero (`prompt > 0 ? cached / prompt : 0`) rather than truthy check.

Helper ships in `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`. Skip `ts-react-vite` (browser doesn't hold OpenRouter keys) and `go-fly-http` (no Go LLM consumer yet).

**D-04a — Per-stack import-path + test-runner matrix** (codex HIGH-1 fix).

| Stack | Source wrapper file | Materialised name | Helper import | Test runner | Test source name |
|---|---|---|---|---|---|
| ts-cloudflare-worker | `lib-observability.ts` | `index.ts` (harness rename) | `from "./index"` | Vitest | `llm-response-meta.test.ts` |
| ts-cloudflare-pages | `lib-observability.ts` | `index.ts` (harness rename) | `from "./index"` | Vitest | `llm-response-meta.test.ts` |
| ts-supabase-edge | `index.ts` (no rename) | `index.ts` | `from "./index.ts"` (Deno explicit-extension) | Deno test | `llm-response-meta.test.ts` |

Worker + pages source-tree files compile against `./index` only after the harness renames `lib-observability.ts` → `index.ts` (matches `meta.yaml target.wrapper_path: src/lib/observability/index.ts` for customer scaffolds). Supabase-edge source-tree is already in materialised form. Helper file content (function body) is identical across all 3 stacks; the import statement is per-stack. Test file content diverges by framework: Vitest `describe/it/expect/vi` vs Deno `Deno.test + assertEquals from "https://deno.land/std@0.224.0/assert/mod.ts"`.

**D-05 — Cache-token field path: `usage.prompt_tokens_details.cached_tokens` with `?? 0` defensive default.** Codex verified against current OpenRouter prompt-caching docs (<https://openrouter.ai/docs/features/prompt-caching>) and OpenAI prompt-caching docs (<https://platform.openai.com/docs/guides/prompt-caching>) — both document this exact field. NO speculative legacy-field fallbacks per codex LOW-2: current docs are clear, fallbacks add complexity for no consumer. `?? 0` handles "field missing" (cache wasn't active) cleanly. If a future drift surfaces, add fallback then — not now. *(OQ-2 resolution.)*

**D-06 — No bundled `pricing.json`.** Sentry AI Monitoring computes cost from its own pricing table; OpenRouter exposes per-call cost via `GET /api/v1/generation?id=<x>`. Local table would rot. Credit-check Worker reads canonical spend via `GET /api/v1/key`. *(OQ-1 resolution.)*

**D-07 — Runbook scope: document both `openAIIntegration` and `anthropicIntegration`, but generically.** No consumer commitment. The runbook also adds a "synthetic / non-user data" carve-out per both reviewers (see D-19 PII gate nuance).

**D-08 — Monitor delivery: standalone scaffold at `add-observability/templates/openrouter-monitor/`.** Not a subcommand. Clearer mental model (Worker you fork or copy). *(OQ-3 resolution.)*

**D-09 — Monitor composition: full wrapper chain, with bundled observability subtree** (codex HIGH-2 + HIGH-3 fix).

The original D-09 said "wraps with withCronMonitor; cron-monitor.ts lives in each stack's template dir already; monitor Worker imports its own copy". Codex caught two blocking issues:

1. **The monitor scaffold needs its own copy of the wrapper subtree**. The proposed `src/index.ts` imports `withCronMonitor` from `./cron-monitor` and `logEvent/captureError` from `./lib-observability` — but those files were NOT in the scaffold's file list. AND the wrapper itself depends on the `destinations/` registry (Sentry adapter + Axiom adapter + role-based dispatch).
2. **The composition `scheduled: withCronMonitor(checkCredit, ...)` alone bypasses `init()`**. `init()` is called by `withObservabilityScheduled` (the layer outside `withCronMonitor`). Without `init()`, the destinations registry is unconfigured, so `logEvent` + `captureError` no-op silently. The monitor would appear instrumented while emitting nothing.

**Revised composition (locked):**

```ts
// add-observability/templates/openrouter-monitor/src/index.ts
import { withSentry } from "@sentry/cloudflare";
import { withObservabilityScheduled } from "./observability/middleware";
import { withCronMonitor } from "./observability/cron-monitor";
import { checkCredit } from "./check-credit";

export default withSentry(
  (env: Env) => ({
    dsn: env.SENTRY_DSN,
    environment: env.DEPLOY_ENV,
    release: env.SERVICE_NAME,
    tracesSampleRate: 0.1,
    sendDefaultPii: false,
    // openAIIntegration NOT needed in the monitor itself — there are no LLM
    // calls from this Worker. Init is only here so logEvent/captureError
    // emit through the destinations registry.
  }),
  {
    scheduled: withObservabilityScheduled(
      withCronMonitor(checkCredit, { monitorSlug: "openrouter-credit-check" })
    ),
  },
);
```

**Scaffold file list (revised)**:

```text
add-observability/templates/openrouter-monitor/
├── package.json
├── wrangler.toml
├── README.md
├── tsconfig.json
└── src/
    ├── check-credit.ts         # the handler logic (separated for testability)
    ├── check-credit.test.ts    # fixtures
    ├── index.ts                # entry point — withSentry composition
    └── observability/          # bundled wrapper subtree (copied from worker template)
        ├── index.ts            # = lib-observability.ts from worker template
        ├── middleware.ts
        ├── cron-monitor.ts
        └── destinations/
            ├── index.ts
            ├── sentry.ts
            └── axiom.ts
```

The observability subtree is copied verbatim from the `ts-cloudflare-worker` template at scaffold authoring time — same per-stack-template-duplication convention used elsewhere. The monitor handler logic (`check-credit.ts`) is what's NEW; the rest is canonical wrapper code.

**D-10 — Monitor env vars (verbatim from PROMPT B).**
- `OPENROUTER_API_KEY` — read-only, `keys:read` scope only (documented in README + STRIDE T1 mitigation).
- `OPENROUTER_WARNING_RATIO` — default `0.85`.
- `OPENROUTER_CRITICAL_RATIO` — default `0.95`.
- Standard `SENTRY_DSN` + `DEPLOY_ENV` + `SERVICE_NAME` + `AXIOM_TOKEN` + `AXIOM_DATASET` per existing wrapper convention.

Cron schedule `*/15 * * * *` (every 15 min).

**D-11 — Monitor handler emits via the bundled wrapper.** `check-credit.ts` calls `logEvent` + `captureError` from `./observability/index` (the bundled wrapper, materialised name). No second `Sentry.init` call inside `check-credit.ts` — Sentry init runs once in `index.ts`'s `withSentry` wrap. Per §10.6: zero hard-coded SDK calls in handler logic. Verification: `grep "Sentry\." add-observability/templates/openrouter-monitor/src/check-credit.ts` returns 0 matches.

**D-12 — Error class hierarchy + severity literals** (codex HIGH-4 fix).

Two named errors emitted via `captureError`:
- `OpenRouterBudgetCriticalError(used_ratio)` — fires when `used_ratio >= OPENROUTER_CRITICAL_RATIO`.
- `OpenRouterHealthcheckFailedError(status)` — fires on non-2xx response from `/api/v1/key` OR on body-parse failure.
- Warning band (`>= WARNING_RATIO` but `< CRITICAL_RATIO`) emits via `logEvent({event:"openrouter.credit_low", severity:"warn", ...})` — **NOTE the literal `"warn"` not `"warning"`** (per `Severity` union in `lib-observability.ts:27` = `"debug" | "info" | "warn" | "error" | "fatal"`). PROMPT B used `"warning"` which is a TS type error — codex caught this.
- Every invocation emits `logEvent({event:"openrouter.credit_pulse", severity:"info", attrs:{used, limit, used_ratio}})` for Axiom time-series.
- Inverted thresholds (`WARNING_RATIO >= CRITICAL_RATIO`) treated as misconfig: emit `logEvent({event:"openrouter.misconfigured_thresholds", severity:"warn", ...})` and fall back to defaults (0.85 / 0.95).

**D-13 — INIT.md Phase 5.5 surface: "Optional: LLM observability" with consent gate 4** (codex MEDIUM-detection-grep fix).

**Detection logic (broadened from package.json + src/ only):**
- (a) `package.json` (top-level) contains `"openai"` or `"@anthropic-ai/sdk"`, OR a workspace `package.json` does (pnpm/yarn/npm workspace globs).
- AND
- (b) any `*.ts` / `*.tsx` / `*.js` / `*.mts` file in the project contains the literal `openrouter.ai` (case-insensitive), OR a `wrangler.toml`/`wrangler.jsonc` `[env.production.vars]` block contains `OPENROUTER_API_KEY`, OR a `.dev.vars`/`.env.example` sets `OPENROUTER_API_KEY`.

This catches Workers, Pages, Supabase, monorepo, and projects that load the key but don't yet have a call site.

When matched, offer three actions (consent gate 4):
- (a) insert `openAIIntegration({recordInputs:false, recordOutputs:false})` (or `anthropicIntegration`) into existing `Sentry.init` integrations array. **Prerequisite**: `@sentry/cloudflare ≥ 10.2.0` (D-17). Detection block warns if version is lower; user updates package.json then re-runs.
- (b) copy `llm-response-meta.ts` into the stack-appropriate target dir, with the per-stack import-path baked in (D-04a).
- (c) skip — already configured / not needed.

Default on `--yes`: (c). Consent gate 4 follows the existing INIT.md gate convention.

**D-14 — ADR number: 0030.** ADR-0029 = cron-monitor SDK composition (Phase 23). ADR-0030 = `docs/decisions/0030-openrouter-integration-sdk-first.md`. Records SDK-first decision + rejected alternatives (raw-fetch `wrapLLMCall`, bundled `pricing.json`, Anthropic-specific helper, CLI subcommand).

**D-15 — Test surface (revised post-review).**

Per-stack helper test (3 files): `llm-response-meta.test.ts` × {worker, pages, supabase-edge}. **7 fixtures per stack**:
1. cache-hit — `{prompt_tokens: 1000, prompt_tokens_details: {cached_tokens: 800}}` → cache_ratio === 0.8.
2. cache-miss — `cached_tokens: 0` → cache_ratio === 0.
3. divide-by-zero — `prompt_tokens: 0` → cache_ratio === 0 (no NaN).
4. missing usage fields — `{}` → all attrs default to 0.
5. missing rate-limit headers — `raw.headers.get` returns null → pass through unchanged.
6. `service` default — `ctx` without `service` → `attrs.service === "openrouter"`.
7. `service` override — `ctx.service === "groq"` → `attrs.service === "groq"`.

Monitor handler tests (1 file): `templates/openrouter-monitor/src/check-credit.test.ts`. **12 fixtures** (added 5 over the original 7 per gemini + codex):
1. under WARNING (usage=10, limit=100) — pulse only.
2. at WARNING exactly (usage=85, limit=100) — pulse + credit_low warn.
3. between WARNING and CRITICAL (usage=90, limit=100) — pulse + credit_low warn.
4. at CRITICAL exactly (usage=95, limit=100) — pulse + `OpenRouterBudgetCriticalError`.
5. 401 from `/api/v1/key` — `OpenRouterHealthcheckFailedError(401)`.
6. 500 from `/api/v1/key` — `OpenRouterHealthcheckFailedError(500)`.
7. **429 rate-limited** — `OpenRouterHealthcheckFailedError(429)` *(gemini + codex)*.
8. **Network throw** — `fetch` rejects with TypeError → `OpenRouterHealthcheckFailedError(0)` *(codex)*.
9. **Malformed JSON body** — `res.json()` throws → `OpenRouterHealthcheckFailedError(-1)` *(gemini + codex)*.
10. **`limit: null`** (OpenRouter unlimited-key shape) — used_ratio computed as 0, pulse only, no warn/critical *(codex)*.
11. **Inverted thresholds** (`WARNING_RATIO=0.95`, `CRITICAL_RATIO=0.85`) — misconfig warn + fall back to defaults *(codex)*.
12. **Invalid threshold env vars** (`OPENROUTER_WARNING_RATIO="not-a-number"` / `"-1"` / `"1.5"`) — falls back to default 0.85.

Plus: `withCronMonitor` fail-safe (DSN unset → handler still runs, per ADR-0029 Guarded Shape A). Tested via the existing `cron-monitor.test.ts` contract suite — not re-tested in the monitor's own suite.

**Harness wiring per-stack** (codex MEDIUM-harness fix):
- **ts-cloudflare-worker**: harness uses explicit substitute_tokens lines. Each Wave 1 task adds 2 lines (one for `.test.ts`, one for `.ts`). RED commit wires `.test.ts`; GREEN commit wires `.ts`.
- **ts-cloudflare-pages**: same as worker — explicit substitute_tokens lines. 2 edits per task.
- **ts-supabase-edge**: harness uses glob `for f in "$SRC"/*.test.ts` (catches new test file automatically), but explicit substitute_tokens for `.ts` impl. RED commit just creates `.test.ts` (auto-picked-up by glob; deno test fails with "Module not found"); GREEN commit adds the `.ts` substitution line. 1 edit per task.

Total: 2+2+1 = 5 substitute_tokens line additions in run-template-tests.sh across Wave 1.

**Net new test surface**: 3 × 7 (helper) + 12 (monitor) = **33 new test cases**. The monitor 12 run via `cd add-observability/templates/openrouter-monitor && npm test` (separate harness — not picked up by `run-template-tests.sh`). The helper 21 ride the existing template harness.

**D-16 — ROADMAP bootstrap deferred.** Phase 24 writes artifacts directly per Phase 23 precedent. Bootstrap is its own phase.

**D-17 — Minimum Sentry SDK version: `@sentry/cloudflare ≥ 10.2.0`** (codex MEDIUM-SDK-version fix). Sentry's OpenAI integration is documented as requiring SDK 10.2.0+ for AI Monitoring (<https://docs.sentry.io/platforms/javascript/guides/cloudflare/tracing/instrumentation/ai-agents-module/>).

Consequences:
- Monitor scaffold `package.json` pins `"@sentry/cloudflare": "^10.2.0"`.
- Runbook §1 leads with the version prerequisite. Example projects on Sentry SDK ≤9.x get an upgrade-first callout.
- INIT.md §5.5 (D-13) checks the installed `@sentry/*` version BEFORE offering action (a). If the version is too low, the user gets an upgrade hint instead of the integration line.

**D-18 — Secret lifecycle in monitor README** (gemini + codex agreed-MEDIUM fix).

README ships with a "Security & Secret Lifecycle" section covering:
- **Key scope (T1 mitigation)**: `keys:read` ONLY. Never the generation key. Leaked generation key burns budget cap.
- **Per-environment keys**: separate `OPENROUTER_API_KEY_DEV` / `OPENROUTER_API_KEY_PROD` (or per-stack secret bindings). Documented rationale: a dev-env leak shouldn't expose prod spend metadata.
- **Rotation cadence**: recommend 90-day rotation. Procedure: create new key in OpenRouter dashboard → `wrangler secret put OPENROUTER_API_KEY` → verify monitor runs with new key → revoke old key. ≤5 min downtime window.
- **Accidental-commit prevention**: `.gitignore` covers `.dev.vars`, `*.env`, `*.env.local`; `wrangler.toml` has secrets as comments only (declaration via `wrangler secret put`, never plaintext). Pre-commit hook recommendation: gitleaks or trufflehog scan for OpenRouter key prefix (`sk-or-`).
- **Leak response**: revoke old key in OpenRouter dashboard FIRST (within minutes — every minute of delay = budget burn), then rotate per above. File a security incident report. Update post-mortem.
- **Operator offboarding**: when an operator leaves, rotate the key (they may have shell history / clipboard / 1Password copy).

These guidelines go in README.md `## Security & Secret Lifecycle` subsection, not in policy.md (the per-project policy doc) — README is the right surface because it travels with the forked scaffold.

**D-19 — PII gate nuance: synthetic / non-user data carve-out** (gemini + codex agreed-MEDIUM fix).

Runbook §2's PII gate is loud about `recordInputs:false / recordOutputs:false` as the default. But it adds a carve-out:

> ⚠️ **Allowed exceptions** — `recordInputs:true / recordOutputs:true` MAY be enabled for **non-user / synthetic / approved-eval-dataset** traces ONLY, with WRITTEN policy approval (`policy.md` consent gate). Concrete examples of acceptable use:
> - Internal synthetic eval traces (no real user data).
> - Replay against canned fixture inputs during regression testing.
> - Approved red-team / probe campaigns where the input is owned by the project, not a customer.
>
> NOT acceptable: ANY trace containing real user prompts, customer payloads, PHI, financial PII, or chat-history.

Same callout structure for `anthropicIntegration` in §3.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Spec
- `~/Sourcecode/agenticapps/agenticapps-workflow-core/spec/10-observability.md` — §10.6 destination-independence (helper + monitor MUST honour); §10.7 host-discretion (no spec change in this phase).

### ADRs (current repo)
- `docs/decisions/0014-observability-architecture.md` — wrapper architecture (init/logEvent/captureError contract).
- `docs/decisions/0029-cron-monitor-sdk-composition.md` — `withCronMonitor` Guarded Shape A.

### Implementation references (current repo)
- `add-observability/SKILL.md` — dispatch table; bump frontmatter to 0.8.0.
- `add-observability/templates/ts-cloudflare-worker/lib-observability.ts:27` — `Severity` union (`"debug" | "info" | "warn" | "error" | "fatal"`); `Envelope` interface (line 30); `logEvent` signature (line 253).
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:115` — `withCronMonitor` export. Lines 1–30 doc-comment cites ADR-0029 + the Guarded Shape A invariants.
- `add-observability/templates/ts-cloudflare-worker/middleware.ts:78` — `withObservabilityScheduled` signature (the layer that calls `init()`).
- `add-observability/templates/ts-cloudflare-worker/destinations/` — destinations registry + Sentry adapter + Axiom adapter (bundled into monitor scaffold per D-09).
- `add-observability/templates/ts-supabase-edge/index.ts` — source-named `index.ts` (no harness rename); imports use Deno `./index.ts` style (per D-04a).
- `add-observability/templates/run-template-tests.sh:128/246/308` — harness substitution lines (worker, pages, supabase-edge respectively); supabase-edge uses `for f in $SRC/*.test.ts` glob for test files.
- `add-observability/init/INIT.md:282-389` — Phase 5 per-stack subsections (anchor for §5.5).
- `add-observability/init/INIT.md:466,477` — existing `sendDefaultPii: false` lines (reference for PII gate doc).

### External docs (verify during execute)
- Sentry AI Monitoring (Cloudflare): <https://docs.sentry.io/platforms/javascript/guides/cloudflare/tracing/instrumentation/ai-agents-module/> — `openAIIntegration` requires SDK ≥10.2.0 (D-17 prerequisite).
- Sentry AI Monitoring (general): <https://docs.sentry.io/product/insights/ai/>.
- OpenRouter API: <https://openrouter.ai/docs> — `GET /api/v1/key` shape (note `limit: null` for unlimited keys per D-15 fixture 10); `GET /api/v1/generation?id=` per-call cost.
- OpenRouter prompt-caching: <https://openrouter.ai/docs/features/prompt-caching> — confirms `usage.prompt_tokens_details.cached_tokens` field path (D-05).
- OpenAI prompt-caching: <https://platform.openai.com/docs/guides/prompt-caching> — same field path (mirrored upstream).

### Out-of-family (informational only; do NOT modify)
- `~/Sourcecode/factiv/callbot/apps/backend/src/llm/client.ts` — example SDK consumer.
- `~/Sourcecode/factiv/fx-signal-agent/apps/worker-agent/src/llm/client.ts` (post-PROMPT C0) — example SDK consumer.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`logEvent(envelope: Envelope)` + `captureError(err, envelope)`** from `lib-observability.ts:253/270` — helper + monitor emit through these.
- **`Envelope = { event: string; severity?: Severity; attrs?: Record<string, unknown> }`** (lib-observability.ts:30) — helper's `event: "llm.call_meta"` slots in.
- **`Severity = "debug" | "info" | "warn" | "error" | "fatal"`** (lib-observability.ts:27) — note `"warn"` not `"warning"` (D-12 binding).
- **`withCronMonitor`** (cron-monitor.ts:115) — Guarded Shape A; monitor wraps `checkCredit` with this.
- **`withObservabilityScheduled`** (middleware.ts:78) — calls `init(env, ctx)`; MUST wrap `withCronMonitor(...)` so the destinations registry is configured before `checkCredit` runs (D-09 fix).
- **`withSentry`** (from `@sentry/cloudflare`) — outermost wrapper in the standard composition chain (`withSentry(env => ({...}), { scheduled: ... })`).

### Established Patterns
- **Per-stack template duplication**: each stack carries its own observability primitives. Monitor scaffold bundles its own copy (D-09).
- **Source-name-vs-materialised-name divergence (worker + pages)**: source is `lib-observability.ts`, materialised as `index.ts`; cross-file imports use `"./index"` to match materialisation.
- **Supabase-edge source = materialised name**: source `index.ts` is already the final name; Deno imports include explicit `.ts` extension (`"./index.ts"`).
- **TDD via the template-test harness**: helper tests sit next to source (`*.test.ts`); RED→GREEN per task. Harness wires `.test.ts` (RED) before `.ts` (GREEN); for ts-supabase-edge the test-file is auto-picked-up by glob (D-15).
- **§10.6 destination-independence**: helper takes `logEvent` by injection; monitor handler emits via bundled wrapper (no direct Sentry calls in handler).

### Integration Points
- Helper `import type { Envelope }`: per-stack — worker/pages `from "./index"`; supabase-edge `from "./index.ts"`. Helper file body otherwise identical across all 3 stacks (D-04a).
- Monitor `index.ts` composes `withSentry(env => ({...}), { scheduled: withObservabilityScheduled(withCronMonitor(checkCredit, {...})) })` (D-09 full chain).
- Monitor scaffold bundles `observability/` subtree (`index.ts` + `middleware.ts` + `cron-monitor.ts` + `destinations/`) at materialise time.
- INIT.md §5.5 surface — broadened detection per D-13.
- CHANGELOG `[1.19.0]` entry at repo root; `## 0.8.0` entry in `add-observability/CHANGELOG.md`.
</code_context>

<specifics>
## Specific Ideas

- Runbook PII callout uses `> ⚠️ **PII GATE**` blockquote; runbook PII carve-out (D-19) uses `> ⚠️ **Allowed exceptions**` blockquote — same loud-style.
- Helper's `service` field default `"openrouter"` is correct for the dominant case but overridable (`service?: string`) for projects routing through Together.ai / Groq / direct Anthropic.
- Monitor's `OPENROUTER_API_KEY` value SHOULD be prefixed with `sk-or-v1-` in real deployment — pre-commit hook recommendation (D-18) scans for this prefix in committed files.
- Consider `OPENROUTER_BUDGET_OVERRIDE` env override — deferred to v0.9.0 (YAGNI for v0.8.0).
- Sentry SDK 10.2.0+ requirement (D-17) means projects on `@sentry/cloudflare ^8.x` (most current callers per Phase 23 templates) need to upgrade before adopting AI Monitoring. The runbook documents the upgrade path; INIT.md §5.5 detects-and-warns.
</specifics>

<deferred>
## Deferred Ideas

### Carried from Phase 23 (still in 0.8.0 candidate backlog)
- **WR-01** — Pages KV signal threading + add `signal?: AbortSignal` to `HealthzEnv.OBSERVABILITY_KV.get` type (advisory).
- **WR-02** — Go upstream body close in timeout branch (advisory).
- **WR-03 / A-01** — `_setWithMonitorForTest` null-restore branch (+ optional build-time gate) (advisory).
- **A-02** — Healthz `/healthz` default → `{ status }` only, opt into `?detail=true` (security advisory).

### New deferrals from this phase
- **Raw-fetch `wrapLLMCall` helper** — rejected per D-03 (no consumer; YAGNI).
- **Bundled `pricing.json` model→cost table** — rejected per D-06.
- **Anthropic-specific helper** — rejected per D-07 (runbook documents the generic path; no consumer yet).
- **Go stack helper** — no Go LLM consumer in scope. Add when one appears.
- **react-vite helper** — browser MUST NOT hold OpenRouter keys.
- **`OPENROUTER_BUDGET_OVERRIDE` ops override** — v0.9.0 candidate.
- **`@sentry/cloudflare ≤ 9.x` AI-Monitoring backport** — out of scope. Projects upgrade to ≥10.2.0 per D-17.

### Workflow gaps (still highest leverage, still outside this PR's scope)
- **ROADMAP.md / STATE.md / REQUIREMENTS.md retroactive bootstrap** — separate phase.
- **GH Actions CI** — gate PRs on `migrations/run-tests.sh` + `templates/run-template-tests.sh all`. Independent of this PR.
- **Upstream `WithMonitor` contribution to `getsentry/sentry-go`** — out of repo scope.

### Scope-creep redirects from this phase's discussion
- None — discussion stayed within the four prompt-prescribed deliverables.
</deferred>

---

*Phase: 24-openrouter-integration*
*Context gathered: 2026-05-29 (--auto, single-pass)*
*Context revised post-review: 2026-05-29 (gemini + codex 4 HIGH + 5 MEDIUM)*
